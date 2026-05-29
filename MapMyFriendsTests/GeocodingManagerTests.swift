//
//  GeocodingManagerTests.swift
//  MapMyFriendsTests
//

import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

struct GeocodingManagerTests {

    private func makeAddress(id: String = "1", name: String = "Test", address: String = "123 Main St") -> ContactsManager.RawContactAddress {
        ContactsManager.RawContactAddress(
            contactID: id,
            fullName: name,
            addressLabel: "Home",
            addressString: address,
            thumbnailImageData: nil,
            phoneNumber: nil
        )
    }

    @Test func allCacheHitsDeliverContacts() {
        let mockCache = MockCacheManager()
        mockCache.storage["123 Main St"] = CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date())
        mockCache.storage["456 Oak Ave"] = CachedCoordinate(lat: 38.0, lng: -121.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolvedCount = 0
        var completeCalled = false

        manager.onContactResolved = { _ in resolvedCount += 1 }
        manager.onComplete = { _ in completeCalled = true }

        manager.process(addresses: [
            makeAddress(id: "1", address: "123 Main St"),
            makeAddress(id: "2", address: "456 Oak Ave"),
        ])

        #expect(resolvedCount == 2)
        #expect(completeCalled)
    }

    @Test func emptyInputCallsComplete() {
        let manager = GeocodingManager(cache: MockCacheManager())
        var completeCalled = false
        manager.onComplete = { _ in completeCalled = true }

        manager.process(addresses: [])

        #expect(completeCalled)
    }

    @Test func cacheHitCoordinatesAreCorrect() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 40.0, lng: -74.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        manager.process(addresses: [makeAddress(address: "addr")])

        #expect(resolved?.coordinate.latitude == 40.0)
        #expect(resolved?.coordinate.longitude == -74.0)
    }

    @Test func cancelTriggersSave() {
        let mockCache = MockCacheManager()
        let manager = GeocodingManager(cache: mockCache)

        manager.cancel()

        #expect(mockCache.saveToDiskCallCount == 1)
    }

    @Test func allCacheHitsDoNotTriggerSave() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        manager.onComplete = { _ in }

        manager.process(addresses: [makeAddress(address: "addr")])

        // With all cache hits and no misses, onComplete fires but saveToDisk is only called
        // in the sequential geocode path. All-hits path does not save (nothing new to persist).
        #expect(mockCache.saveToDiskCallCount == 0)
    }

    @Test func resolvedContactPreservesMetadata() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        let address = ContactsManager.RawContactAddress(
            contactID: "xyz",
            fullName: "John Smith",
            addressLabel: "Work",
            addressString: "addr",
            thumbnailImageData: nil,
            phoneNumber: "+14155550000"
        )
        manager.process(addresses: [address])

        #expect(resolved?.contactID == "xyz")
        #expect(resolved?.fullName == "John Smith")
        #expect(resolved?.addressLabel == "Work")
        #expect(resolved?.addressString == "addr")
    }

    @Test func resolvedContactPreservesPhoneNumber() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        let address = ContactsManager.RawContactAddress(
            contactID: "ph-test",
            fullName: "Phone User",
            addressLabel: "Home",
            addressString: "addr",
            thumbnailImageData: nil,
            phoneNumber: "+1 (415) 555-0199"
        )
        manager.process(addresses: [address])

        #expect(resolved?.phoneNumber == "+1 (415) 555-0199")
    }

    @Test func resolvedContactPreservesNilPhoneNumber() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        manager.process(addresses: [makeAddress(address: "addr")])

        #expect(resolved?.phoneNumber == nil)
    }

    // MARK: - Failed Entry Handling

    @Test func failedCacheEntryIsSkippedSilently() {
        let mockCache = MockCacheManager()
        mockCache.storage["bad_addr"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)

        let manager = GeocodingManager(cache: mockCache)
        var resolvedCount = 0
        var completeFailedCount = -1

        manager.onContactResolved = { _ in resolvedCount += 1 }
        manager.onComplete = { completeFailedCount = $0 }

        manager.process(addresses: [makeAddress(address: "bad_addr")])

        #expect(resolvedCount == 0, "Failed cache entry should not resolve a contact")
        #expect(completeFailedCount == 0, "No geocoding attempted, so 0 failures")
    }

    @Test func mixOfSuccessAndFailedCacheEntries() {
        let mockCache = MockCacheManager()
        mockCache.storage["good"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())
        mockCache.storage["bad"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)

        let manager = GeocodingManager(cache: mockCache)
        var resolvedCount = 0
        manager.onContactResolved = { _ in resolvedCount += 1 }
        manager.onComplete = { _ in }

        manager.process(addresses: [
            makeAddress(id: "1", address: "good"),
            makeAddress(id: "2", address: "bad"),
        ])

        #expect(resolvedCount == 1, "Only the non-failed entry should resolve")
    }

    @Test func onCompleteReportsZeroForAllCacheHits() {
        let mockCache = MockCacheManager()
        mockCache.storage["a"] = CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var failedCount = -1
        manager.onComplete = { failedCount = $0 }

        manager.process(addresses: [makeAddress(address: "a")])

        #expect(failedCount == 0)
    }

    // MARK: - Proximity Sorting

    @Test func cacheHitsSortedByProximityToUser() {
        let mockCache = MockCacheManager()
        // "far" is further from user (0,0) than "near"
        mockCache.storage["far"] = CachedCoordinate(lat: 40.0, lng: -74.0, cachedAt: Date())
        mockCache.storage["near"] = CachedCoordinate(lat: 0.1, lng: 0.1, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolvedOrder: [String] = []
        manager.onContactResolved = { resolvedOrder.append($0.addressString) }
        manager.onComplete = { _ in }

        let userLocation = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        manager.process(addresses: [
            makeAddress(id: "1", address: "far"),
            makeAddress(id: "2", address: "near"),
        ], userLocation: userLocation)

        #expect(resolvedOrder == ["near", "far"], "Nearest contact should be resolved first")
    }

    @Test func noUserLocationPreservesOriginalOrder() {
        let mockCache = MockCacheManager()
        mockCache.storage["b"] = CachedCoordinate(lat: 40.0, lng: -74.0, cachedAt: Date())
        mockCache.storage["a"] = CachedCoordinate(lat: 0.1, lng: 0.1, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolvedOrder: [String] = []
        manager.onContactResolved = { resolvedOrder.append($0.addressString) }
        manager.onComplete = { _ in }

        manager.process(addresses: [
            makeAddress(id: "1", address: "b"),
            makeAddress(id: "2", address: "a"),
        ])

        #expect(resolvedOrder == ["b", "a"], "Without user location, original order is preserved")
    }
}
