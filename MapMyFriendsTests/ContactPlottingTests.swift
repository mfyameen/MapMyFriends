//
//  ContactPlottingTests.swift
//  MapMyFriendsTests
//
//  Comprehensive tests for the contact address → geocode → plot pipeline.
//  Covers cache hits, misses, failures, TTL expiry, proximity sorting,
//  and edge cases that previously caused regressions.
//

import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

struct ContactPlottingTests {

    // MARK: - Helpers

    private func makeAddress(
        id: String = "1",
        name: String = "Test User",
        address: String = "123 Main St"
    ) -> ContactsManager.RawContactAddress {
        ContactsManager.RawContactAddress(
            contactID: id,
            fullName: name,
            addressLabel: "Home",
            addressString: address,
            thumbnailImageData: nil,
            phoneNumber: nil
        )
    }

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    // MARK: - 1. Basic Cache Hit Resolution

    @Test func cachedAddressResolvesToPin() {
        let mock = MockCacheManager()
        mock.storage["123 Main St"] = CachedCoordinate(lat: 37.7749, lng: -122.4194, cachedAt: Date())

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress()])

        #expect(resolved.count == 1)
        #expect(resolved.first?.fullName == "Test User")
        #expect(resolved.first?.coordinate.latitude == 37.7749)
    }

    @Test func multipleCachedAddressesAllResolve() {
        let mock = MockCacheManager()
        mock.storage["addr1"] = CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date())
        mock.storage["addr2"] = CachedCoordinate(lat: 2.0, lng: 2.0, cachedAt: Date())
        mock.storage["addr3"] = CachedCoordinate(lat: 3.0, lng: 3.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [
            makeAddress(id: "a", address: "addr1"),
            makeAddress(id: "b", address: "addr2"),
            makeAddress(id: "c", address: "addr3"),
        ])

        #expect(resolved.count == 3, "All 3 cached addresses should resolve")
    }

    // MARK: - 2. Cache Miss Handling

    @Test func uncachedAddressBecomesCacheMiss() {
        let mock = MockCacheManager()
        // No entries in cache

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        var completeFailedCount = -1
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { completeFailedCount = $0 }

        // With no cache entries, the address is a miss. Since we can't actually geocode
        // in tests, we just verify it doesn't resolve from cache.
        manager.process(addresses: [makeAddress()])

        #expect(resolved.isEmpty, "Uncached address should not resolve immediately from cache")
        // onComplete won't fire synchronously since there are cache misses to geocode
    }

    // MARK: - 3. Failed Entry Behavior

    @Test func failedEntryDoesNotResolve() {
        let mock = MockCacheManager()
        mock.storage["bad"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress(address: "bad")])

        #expect(resolved.isEmpty, "Failed cache entry should never resolve to a pin")
    }

    @Test func failedEntryIsNotRetried() {
        let mock = MockCacheManager()
        mock.storage["bad"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)

        let manager = GeocodingManager(cache: mock)
        var completeFailed = -1
        manager.onComplete = { completeFailed = $0 }

        manager.process(addresses: [makeAddress(address: "bad")])

        // The failed entry is skipped (continue), so no cache misses, onComplete fires with 0
        #expect(completeFailed == 0, "Failed entry should not trigger re-geocoding")
    }

    @Test func successfulEntryNotConfusedWithFailed() {
        let mock = MockCacheManager()
        mock.storage["good"] = CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date(), failed: false)

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress(address: "good")])

        #expect(resolved.count == 1, "Non-failed cache entry must resolve")
    }

    // MARK: - 4. TTL Expiry

    @Test func staleSuccessBecomesaCacheMiss() {
        // Use real CacheManager with short TTL
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 1, failedTtl: 1)
        let staleDate = Date(timeIntervalSinceNow: -10) // 10 seconds ago, TTL is 1s
        cache.store(coordinate: CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: staleDate), for: "addr")

        let manager = GeocodingManager(cache: cache)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }

        manager.process(addresses: [makeAddress(address: "addr")])

        #expect(resolved.isEmpty, "Stale successful entry should NOT resolve — should become cache miss")
    }

    @Test func staleFailedEntryIsRetried() {
        // Use real CacheManager with short failed TTL
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 1)
        let staleDate = Date(timeIntervalSinceNow: -10) // 10 seconds ago, failed TTL is 1s
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: staleDate, failed: true), for: "addr")

        let manager = GeocodingManager(cache: cache)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }

        manager.process(addresses: [makeAddress(address: "addr")])

        // The stale failed entry returns nil from cache, so the address becomes a cache miss.
        // It won't resolve immediately (needs geocoding), but it's not silently dropped.
        #expect(resolved.isEmpty, "Stale failed entry should become cache miss, not resolve from cache")
    }

    @Test func freshFailedEntryUsesShortTTL() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 5)
        // Fresh failed entry (just now) — should be found by cache lookup
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true), for: "addr")

        let result = cache.coordinate(for: "addr")
        #expect(result != nil, "Fresh failed entry should be returned")
        #expect(result?.failed == true)
    }

    @Test func expiredFailedEntryReturnsNil() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 1)
        let staleDate = Date(timeIntervalSinceNow: -10)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: staleDate, failed: true), for: "addr")

        let result = cache.coordinate(for: "addr")
        #expect(result == nil, "Expired failed entry should return nil to trigger retry")
    }

    // MARK: - 5. Mixed Scenarios

    @Test func mixOfHitsFailedAndMisses() {
        let mock = MockCacheManager()
        mock.storage["cached"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())
        mock.storage["failed"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)
        // "uncached" is not in storage → cache miss

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [
            makeAddress(id: "1", address: "cached"),
            makeAddress(id: "2", address: "failed"),
            makeAddress(id: "3", address: "uncached"),
        ])

        #expect(resolved.count == 1, "Only the successful cache hit should resolve")
        #expect(resolved.first?.contactID == "1")
    }

    @Test func contactWithMultipleAddresses() {
        let mock = MockCacheManager()
        mock.storage["home"] = CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date())
        mock.storage["work"] = CachedCoordinate(lat: 40.0, lng: -74.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mock)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [
            ContactsManager.RawContactAddress(
                contactID: "same-person",
                fullName: "Jane Doe",
                addressLabel: "Home",
                addressString: "home",
                thumbnailImageData: nil,
                phoneNumber: nil
            ),
            ContactsManager.RawContactAddress(
                contactID: "same-person",
                fullName: "Jane Doe",
                addressLabel: "Work",
                addressString: "work",
                thumbnailImageData: nil,
                phoneNumber: nil
            ),
        ])

        #expect(resolved.count == 2, "Both addresses for the same contact should resolve as separate pins")
        let labels = Set(resolved.map(\.addressLabel))
        #expect(labels == ["Home", "Work"])
    }

    // MARK: - 6. Metadata Passthrough

    @Test func allMetadataPreservedThroughCacheHit() {
        let mock = MockCacheManager()
        mock.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mock)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }
        manager.onComplete = { _ in }

        let imageData = Data([0xFF, 0xD8])
        let address = ContactsManager.RawContactAddress(
            contactID: "id-123",
            fullName: "Full Name",
            addressLabel: "Work",
            addressString: "addr",
            thumbnailImageData: imageData,
            phoneNumber: "+15551234567"
        )
        manager.process(addresses: [address])

        #expect(resolved?.contactID == "id-123")
        #expect(resolved?.fullName == "Full Name")
        #expect(resolved?.addressLabel == "Work")
        #expect(resolved?.addressString == "addr")
        #expect(resolved?.thumbnailImageData == imageData)
        #expect(resolved?.phoneNumber == "+15551234567")
        #expect(resolved?.coordinate.latitude == 1.0)
        #expect(resolved?.coordinate.longitude == 2.0)
    }

    // MARK: - 7. Proximity Sorting

    @Test func proximitySortOrdersNearestFirst() {
        let mock = MockCacheManager()
        mock.storage["far"]  = CachedCoordinate(lat: 48.8566, lng: 2.3522, cachedAt: Date())  // Paris
        mock.storage["mid"]  = CachedCoordinate(lat: 40.7128, lng: -74.006, cachedAt: Date())  // NYC
        mock.storage["near"] = CachedCoordinate(lat: 37.7749, lng: -122.4194, cachedAt: Date()) // SF

        let manager = GeocodingManager(cache: mock)
        var order: [String] = []
        manager.onContactResolved = { order.append($0.addressString) }
        manager.onComplete = { _ in }

        // User is in SF
        let sf = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)
        manager.process(addresses: [
            makeAddress(id: "1", address: "far"),
            makeAddress(id: "2", address: "mid"),
            makeAddress(id: "3", address: "near"),
        ], userLocation: sf)

        #expect(order == ["near", "mid", "far"], "Should resolve nearest to farthest")
    }

    // MARK: - 8. Process Stability

    @Test func callingProcessTwiceDoesNotDuplicateHits() {
        let mock = MockCacheManager()
        mock.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mock)
        var resolvedCount = 0
        manager.onContactResolved = { _ in resolvedCount += 1 }
        manager.onComplete = { _ in }

        let addr = makeAddress(address: "addr")
        manager.process(addresses: [addr])
        manager.process(addresses: [addr])

        #expect(resolvedCount == 2, "Each process call should resolve independently")
    }

    @Test func emptyAddressListCompletesImmediately() {
        let mock = MockCacheManager()
        let manager = GeocodingManager(cache: mock)
        var completeCalled = false
        var failedCount = -1
        manager.onComplete = { count in
            completeCalled = true
            failedCount = count
        }

        manager.process(addresses: [])

        #expect(completeCalled)
        #expect(failedCount == 0)
    }

    // MARK: - 9. Cache Persistence Integration

    @Test func successfulEntryPersistsAcrossReloads() {
        let url = makeTempFileURL()
        let cache1 = CacheManager(fileURL: url)
        cache1.store(coordinate: CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date()), for: "addr")
        cache1.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        let manager = GeocodingManager(cache: cache2)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress(address: "addr")])

        #expect(resolved.count == 1, "Entry saved to disk should survive reload and resolve")
    }

    @Test func failedEntryPersistsAcrossReloads() {
        let url = makeTempFileURL()
        let cache1 = CacheManager(fileURL: url)
        cache1.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true), for: "bad")
        cache1.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        let manager = GeocodingManager(cache: cache2)
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress(address: "bad")])

        #expect(resolved.isEmpty, "Failed entry should persist across reload and still be skipped")
    }

    // MARK: - 10. Separate TTLs for Success vs Failed

    @Test func successUsesLongTTLAndFailedUsesShortTTL() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 5)

        // Store a 30-second-old success — should still be valid (TTL is 3600)
        let recentDate = Date(timeIntervalSinceNow: -30)
        cache.store(coordinate: CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: recentDate), for: "good")

        // Store a 30-second-old failure — should be expired (failed TTL is 5)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: recentDate, failed: true), for: "bad")

        #expect(cache.coordinate(for: "good") != nil, "30s-old success should be valid with 3600s TTL")
        #expect(cache.coordinate(for: "bad") == nil, "30s-old failure should be expired with 5s TTL")
    }
}
