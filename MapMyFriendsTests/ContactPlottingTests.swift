//
//  ContactPlottingTests.swift
//  MapMyFriendsTests
//
//  Comprehensive tests for the contact address → geocode → plot pipeline.
//  Covers cache hits, misses, legacy failure entries, TTL expiry, proximity sorting,
//  and the ten use cases from the contact-plotting bug investigation.
//
//  Geocoding runs through `MockGeocoder` with `requestDelay: 0`, so a whole run
//  completes synchronously inside `process()` and never touches the network.
//

import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

struct ContactPlottingTests {

    // MARK: - Helpers

    private struct RunResult {
        var resolved: [MappedContact] = []
        var progressEvents: [(completed: Int, total: Int)] = []
        var summary: GeocodingManager.Summary?
        var reportedFailureCount: Int?
    }

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

    /// Builds `count` addresses named `<prefix>-0 ... <prefix>-(count-1)`.
    private func makeAddresses(count: Int, prefix: String = "addr") -> [ContactsManager.RawContactAddress] {
        (0..<count).map { makeAddress(id: "\($0)", name: "Contact \($0)", address: "\(prefix)-\($0)") }
    }

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func makeManager(cache: CacheManaging, geocoder: AddressGeocoding) -> GeocodingManager {
        GeocodingManager(cache: cache, geocoder: geocoder, requestDelay: 0)
    }

    /// Runs `process()` to completion and captures everything the manager reported.
    private func run(
        _ manager: GeocodingManager,
        addresses: [ContactsManager.RawContactAddress],
        userLocation: CLLocationCoordinate2D? = nil
    ) -> RunResult {
        var result = RunResult()
        manager.onContactResolved = { result.resolved.append($0) }
        manager.onProgress = { completed, total in result.progressEvents.append((completed, total)) }
        manager.onSummary = { result.summary = $0 }
        manager.onComplete = { result.reportedFailureCount = $0 }

        manager.process(addresses: addresses, userLocation: userLocation)
        return result
    }

    // MARK: - 1. Basic Cache Hit Resolution

    @Test func cachedAddressResolvesToPin() {
        let cache = MockCacheManager()
        cache.storeSuccess("123 Main St", lat: 37.7749, lng: -122.4194)

        let result = run(makeManager(cache: cache, geocoder: MockGeocoder()), addresses: [makeAddress()])

        #expect(result.resolved.count == 1)
        #expect(result.resolved.first?.fullName == "Test User")
        #expect(result.resolved.first?.coordinate.latitude == 37.7749)
    }

    @Test func multipleCachedAddressesAllResolve() {
        let cache = MockCacheManager()
        cache.storeSuccess("addr-0", lat: 1.0, lng: 1.0)
        cache.storeSuccess("addr-1", lat: 2.0, lng: 2.0)
        cache.storeSuccess("addr-2", lat: 3.0, lng: 3.0)

        let result = run(
            makeManager(cache: cache, geocoder: MockGeocoder()),
            addresses: makeAddresses(count: 3)
        )

        #expect(result.resolved.count == 3, "All 3 cached addresses should resolve")
        #expect(result.summary?.resolvedFromCache == 3)
    }

    // MARK: - 2. Cache Miss Handling

    @Test func uncachedAddressIsGeocoded() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder()
        geocoder.succeed("123 Main St", lat: 10.0, lng: 20.0)

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: [makeAddress()])

        #expect(geocoder.requestedAddresses == ["123 Main St"])
        #expect(result.resolved.count == 1)
        #expect(result.summary?.geocoded == 1)
        #expect(cache.coordinate(for: "123 Main St")?.lat == 10.0, "Successful geocode must be cached")
    }

    // MARK: - 3. Legacy Failed Entry Behavior

    @Test func legacyFailedEntryIsRetriedNotSkipped() {
        let cache = MockCacheManager()
        cache.storeLegacyFailure("bad")
        let geocoder = MockGeocoder()
        geocoder.succeed("bad", lat: 5.0, lng: 6.0)

        let result = run(
            makeManager(cache: cache, geocoder: geocoder),
            addresses: [makeAddress(address: "bad")]
        )

        #expect(geocoder.requestedAddresses == ["bad"], "Legacy failure must be retried, not dropped")
        #expect(result.resolved.count == 1, "A retry that succeeds must produce a pin")
        #expect(result.summary?.retriedCachedFailures == 1)
    }

    @Test func legacyFailedEntryNeverResolvesFromCacheDirectly() {
        let cache = MockCacheManager()
        cache.storeLegacyFailure("bad")
        let geocoder = MockGeocoder()
        geocoder.fail("bad")

        let result = run(
            makeManager(cache: cache, geocoder: geocoder),
            addresses: [makeAddress(address: "bad")]
        )

        #expect(result.resolved.isEmpty, "A 0,0 failure entry must never be plotted as a pin")
        #expect(result.summary?.failed == 1)
    }

    @Test func successfulEntryNotConfusedWithFailed() {
        let cache = MockCacheManager()
        cache.storeSuccess("good", lat: 37.0, lng: -122.0)

        let result = run(
            makeManager(cache: cache, geocoder: MockGeocoder()),
            addresses: [makeAddress(address: "good")]
        )

        #expect(result.resolved.count == 1, "Non-failed cache entry must resolve")
    }

    // MARK: - 4. Failures Are Never Cached

    @Test func geocodeFailureIsNotCached() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder()
        geocoder.fail("addr-0", reason: "timeout")

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: makeAddresses(count: 1))

        #expect(result.summary?.failed == 1)
        #expect(cache.storedFailureCount == 0, "Transient failures must not be persisted")
        #expect(cache.coordinate(for: "addr-0") == nil, "Nothing should be cached for a failed address")
    }

    @Test func invalidAddressStringIsNotCached() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder()
        geocoder.markInvalid("addr-0")

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: makeAddresses(count: 1))

        #expect(result.summary?.invalidAddressStrings == 1)
        #expect(result.summary?.failed == 1, "Invalid strings count toward the failure total")
        #expect(cache.storedFailureCount == 0)
    }

    // MARK: - 5. TTL Expiry

    @Test func staleSuccessIsReGeocoded() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 1, failedTtl: 1)
        let staleDate = Date(timeIntervalSinceNow: -10) // TTL is 1s
        cache.store(coordinate: CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: staleDate), for: "addr")

        let geocoder = MockGeocoder()
        geocoder.succeed("addr", lat: 1.0, lng: 2.0)

        let result = run(
            makeManager(cache: cache, geocoder: geocoder),
            addresses: [makeAddress(address: "addr")]
        )

        #expect(result.summary?.resolvedFromCache == 0, "Stale entry must not resolve from cache")
        #expect(result.summary?.geocoded == 1, "Stale entry should be re-geocoded")
        #expect(result.resolved.first?.coordinate.latitude == 1.0, "Fresh coordinate should win")
    }

    @Test func expiredLegacyFailedEntryReturnsNil() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 1)
        let staleDate = Date(timeIntervalSinceNow: -10)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: staleDate, failed: true), for: "addr")

        #expect(cache.coordinate(for: "addr") == nil, "Expired failed entry should return nil")
    }

    @Test func freshLegacyFailedEntryIsStillReturnedByCache() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 3600, failedTtl: 5)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true), for: "addr")

        let entry = cache.coordinate(for: "addr")
        #expect(entry?.failed == true, "Cache still surfaces the entry; GeocodingManager decides to retry it")
    }

    // MARK: - 6. Metadata Passthrough

    @Test func allMetadataPreservedThroughCacheHit() {
        let cache = MockCacheManager()
        cache.storeSuccess("addr", lat: 1.0, lng: 2.0)

        let imageData = Data([0xFF, 0xD8])
        let address = ContactsManager.RawContactAddress(
            contactID: "id-123",
            fullName: "Full Name",
            addressLabel: "Work",
            addressString: "addr",
            thumbnailImageData: imageData,
            phoneNumber: "+15551234567"
        )

        let result = run(makeManager(cache: cache, geocoder: MockGeocoder()), addresses: [address])
        let resolved = result.resolved.first

        #expect(resolved?.contactID == "id-123")
        #expect(resolved?.fullName == "Full Name")
        #expect(resolved?.addressLabel == "Work")
        #expect(resolved?.addressString == "addr")
        #expect(resolved?.thumbnailImageData == imageData)
        #expect(resolved?.phoneNumber == "+15551234567")
        #expect(resolved?.coordinate.latitude == 1.0)
        #expect(resolved?.coordinate.longitude == 2.0)
    }

    @Test func metadataPreservedThroughGeocode() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder()
        geocoder.succeed("addr", lat: 3.0, lng: 4.0)

        let address = ContactsManager.RawContactAddress(
            contactID: "geo-1",
            fullName: "Geo User",
            addressLabel: "Work",
            addressString: "addr",
            thumbnailImageData: nil,
            phoneNumber: "+15559999999"
        )

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: [address])

        #expect(result.resolved.first?.contactID == "geo-1")
        #expect(result.resolved.first?.phoneNumber == "+15559999999")
        #expect(result.resolved.first?.coordinate.latitude == 3.0)
    }

    // MARK: - 7. Proximity Sorting

    @Test func proximitySortOrdersNearestFirst() {
        let cache = MockCacheManager()
        cache.storeSuccess("far", lat: 48.8566, lng: 2.3522)     // Paris
        cache.storeSuccess("mid", lat: 40.7128, lng: -74.006)    // NYC
        cache.storeSuccess("near", lat: 37.7749, lng: -122.4194) // SF

        let sf = CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)
        let result = run(
            makeManager(cache: cache, geocoder: MockGeocoder()),
            addresses: [
                makeAddress(id: "1", address: "far"),
                makeAddress(id: "2", address: "mid"),
                makeAddress(id: "3", address: "near"),
            ],
            userLocation: sf
        )

        #expect(result.resolved.map(\.addressString) == ["near", "mid", "far"])
    }

    // MARK: - 8. Process Stability

    @Test func callingProcessTwiceDoesNotDuplicateHits() {
        let cache = MockCacheManager()
        cache.storeSuccess("addr")

        let manager = makeManager(cache: cache, geocoder: MockGeocoder())
        let addresses = [makeAddress(address: "addr")]

        let first = run(manager, addresses: addresses)
        let second = run(manager, addresses: addresses)

        #expect(first.resolved.count == 1)
        #expect(second.resolved.count == 1, "Each process call resolves independently")
        #expect(second.summary?.resolvedFromCache == 1, "Counters reset between runs")
    }

    @Test func emptyAddressListCompletesImmediately() {
        let result = run(makeManager(cache: MockCacheManager(), geocoder: MockGeocoder()), addresses: [])

        #expect(result.reportedFailureCount == 0)
        #expect(result.summary == GeocodingManager.Summary())
    }

    @Test func cancelStopsInFlightRequestAndPersists() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder.alwaysSucceeding()
        let manager = makeManager(cache: cache, geocoder: geocoder)

        manager.cancel()

        #expect(geocoder.cancelInFlightCallCount == 1)
        #expect(cache.saveToDiskCallCount == 1, "Cancel should persist whatever progress was made")
    }

    // MARK: - 9. Cache Persistence Integration

    @Test func successfulEntryPersistsAcrossReloads() {
        let url = makeTempFileURL()
        let first = CacheManager(fileURL: url)
        first.store(coordinate: CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date()), for: "addr")
        first.saveToDisk()

        let reloaded = CacheManager(fileURL: url)
        let result = run(
            makeManager(cache: reloaded, geocoder: MockGeocoder()),
            addresses: [makeAddress(address: "addr")]
        )

        #expect(result.resolved.count == 1, "Entry saved to disk should survive reload and resolve")
    }

    @Test func legacyFailedEntryOnDiskIsRetriedAfterReload() {
        let url = makeTempFileURL()
        let first = CacheManager(fileURL: url)
        first.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true), for: "bad")
        first.saveToDisk()

        let reloaded = CacheManager(fileURL: url)
        let geocoder = MockGeocoder()
        geocoder.succeed("bad", lat: 9.0, lng: 9.0)

        let result = run(
            makeManager(cache: reloaded, geocoder: geocoder),
            addresses: [makeAddress(address: "bad")]
        )

        #expect(geocoder.requestedAddresses == ["bad"], "Persisted legacy failures must be retried")
        #expect(result.resolved.count == 1)
    }

    // MARK: - 10. Use Cases UC1–UC10

    /// UC1: Cold start with an empty cache — everything is geocoded and plotted.
    @Test func uc1_coldStartGeocodesEverything() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder.alwaysSucceeding()

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: makeAddresses(count: 50))

        #expect(result.resolved.count == 50)
        #expect(result.summary?.geocoded == 50)
        #expect(result.summary?.failed == 0)
        #expect(result.reportedFailureCount == 0)
        #expect(cache.storage.count == 50, "Every success should be cached")
        #expect(cache.storedFailureCount == 0)
    }

    /// UC2: Warm start with a full cache — instant pins, no geocoding, no progress banner.
    @Test func uc2_warmStartResolvesEntirelyFromCache() {
        let cache = MockCacheManager()
        let addresses = makeAddresses(count: 50)
        for address in addresses {
            cache.storeSuccess(address.addressString, lat: 37.0, lng: -122.0)
        }
        let geocoder = MockGeocoder()

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: addresses)

        #expect(result.resolved.count == 50)
        #expect(result.summary?.resolvedFromCache == 50)
        #expect(result.summary?.geocoded == 0)
        #expect(geocoder.requestedAddresses.isEmpty, "No geocoding on a fully warm cache")
        #expect(result.progressEvents.isEmpty, "No progress events means no banner")
        #expect(cache.saveToDiskCallCount == 0, "Nothing new to persist")
    }

    /// UC3: Warm start plus newly added contacts — cached pins plus geocoded new ones.
    @Test func uc3_warmStartWithNewContacts() {
        let cache = MockCacheManager()
        let cached = makeAddresses(count: 50, prefix: "cached")
        for address in cached {
            cache.storeSuccess(address.addressString)
        }
        let fresh = makeAddresses(count: 5, prefix: "new")
        let geocoder = MockGeocoder.alwaysSucceeding()

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: cached + fresh)

        #expect(result.resolved.count == 55)
        #expect(result.summary?.resolvedFromCache == 50)
        #expect(result.summary?.geocoded == 5)
        #expect(geocoder.requestedAddresses.count == 5, "Only the new addresses are geocoded")
    }

    /// UC4: Transient geocoding failures are not cached, so the next launch retries them.
    @Test func uc4_transientFailuresRetryOnNextLaunch() {
        let cache = MockCacheManager()
        let addresses = makeAddresses(count: 50)
        let failing = ["addr-7", "addr-19", "addr-33"]

        let firstGeocoder = MockGeocoder.alwaysSucceeding()
        for address in failing {
            firstGeocoder.fail(address)
        }

        let firstRun = run(makeManager(cache: cache, geocoder: firstGeocoder), addresses: addresses)

        #expect(firstRun.resolved.count == 47)
        #expect(firstRun.summary?.failed == 3)
        #expect(cache.storedFailureCount == 0, "Transient failures must not be cached")
        for address in failing {
            #expect(cache.coordinate(for: address) == nil)
        }

        // Next launch: the network is healthy again.
        let secondGeocoder = MockGeocoder.alwaysSucceeding()
        let secondRun = run(makeManager(cache: cache, geocoder: secondGeocoder), addresses: addresses)

        #expect(secondGeocoder.requestedAddresses.sorted() == failing.sorted(), "Only the 3 failures retry")
        #expect(secondRun.resolved.count == 50, "All 50 contacts now appear")
        #expect(secondRun.summary?.resolvedFromCache == 47)
        #expect(secondRun.summary?.geocoded == 3)
    }

    /// UC5: The permission-grant notification must not interrupt the initial geocoding pass.
    @Test func uc5_storeChangeDuringInitialLoadIsDeferred() {
        let coalescer = ContactChangeCoalescer()

        #expect(coalescer.noteChange() == .deferUntilInitialLoadCompletes)
        #expect(coalescer.hasPendingChange)
        #expect(coalescer.noteInitialLoadComplete(), "Deferred change should run once the load finishes")
        #expect(coalescer.noteChange() == .scheduleRefresh, "Later changes refresh immediately")
    }

    @Test func uc5_initialGeocodingCompletesDespiteStoreChangeMidRun() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder.alwaysSucceeding()
        let manager = makeManager(cache: cache, geocoder: geocoder)
        let coalescer = ContactChangeCoalescer()

        var decisionMidRun: ContactChangeCoalescer.Decision?
        var resolved: [MappedContact] = []
        manager.onContactResolved = { resolved.append($0) }
        manager.onProgress = { completed, _ in
            // A store change lands after the first geocode, as a permission grant would.
            if completed == 1, decisionMidRun == nil {
                decisionMidRun = coalescer.noteChange()
            }
        }
        manager.onComplete = { _ in _ = coalescer.noteInitialLoadComplete() }

        manager.process(addresses: makeAddresses(count: 20))

        #expect(decisionMidRun == .deferUntilInitialLoadCompletes, "Must not cancel the initial pass")
        #expect(resolved.count == 20, "Every contact still gets plotted")
        #expect(coalescer.isInitialLoadComplete)
    }

    /// UC6: A contact deleted between launches has its pin removed by the diff.
    @Test func uc6_deletedContactIsRemovedByDiff() {
        let existing = (0..<50).map { index in
            MappedContact(
                contactID: "\(index)",
                fullName: "Contact \(index)",
                addressLabel: "Home",
                addressString: "addr-\(index)",
                coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2),
                thumbnailImageData: nil,
                phoneNumber: nil
            )
        }
        let remaining = makeAddresses(count: 50).filter { $0.contactID != "12" }

        let diff = ContactDiffer.diff(newAddresses: remaining, existing: existing)

        #expect(diff.toRemoveIndices == [12], "Only the deleted contact is removed")
        #expect(diff.toAdd.isEmpty, "Nothing new to geocode")
    }

    /// UC7: An unparseable address is skipped this run and retried on the next one.
    @Test func uc7_invalidAddressIsRetriedNextLaunch() {
        let cache = MockCacheManager()
        let firstGeocoder = MockGeocoder.alwaysSucceeding()
        firstGeocoder.markInvalid("addr-0")

        let firstRun = run(makeManager(cache: cache, geocoder: firstGeocoder), addresses: makeAddresses(count: 3))

        #expect(firstRun.resolved.count == 2)
        #expect(firstRun.summary?.invalidAddressStrings == 1)
        #expect(cache.coordinate(for: "addr-0") == nil, "Invalid strings must not be cached")

        let secondGeocoder = MockGeocoder.alwaysSucceeding()
        let secondRun = run(makeManager(cache: cache, geocoder: secondGeocoder), addresses: makeAddresses(count: 3))

        #expect(secondGeocoder.requestedAddresses == ["addr-0"], "The invalid address is retried")
        #expect(secondRun.resolved.count == 3)
    }

    /// UC8: Regression reproduction — a cache full of legacy failures used to plot nothing.
    @Test func uc8_cacheFullOfLegacyFailuresIsFullyRetried() {
        let cache = MockCacheManager()
        let addresses = makeAddresses(count: 50)
        for address in addresses {
            cache.storeLegacyFailure(address.addressString)
        }
        let geocoder = MockGeocoder.alwaysSucceeding()

        let result = run(makeManager(cache: cache, geocoder: geocoder), addresses: addresses)

        #expect(geocoder.requestedAddresses.count == 50, "All 50 must be retried, not skipped")
        #expect(result.resolved.count == 50, "Previously invisible contacts now appear")
        #expect(result.summary?.retriedCachedFailures == 50)
        #expect(result.summary?.resolvedFromCache == 0)
        #expect(cache.storedFailureCount == 0, "Retried successes overwrite the legacy failure entries")
    }

    /// UC9: Mixed cache state — hits resolve, legacy failures retry, misses geocode.
    @Test func uc9_mixOfHitsLegacyFailuresAndMisses() {
        let cache = MockCacheManager()
        let hits = makeAddresses(count: 30, prefix: "hit")
        let legacyFailures = makeAddresses(count: 10, prefix: "legacy")
        let misses = makeAddresses(count: 10, prefix: "miss")

        for address in hits {
            cache.storeSuccess(address.addressString)
        }
        for address in legacyFailures {
            cache.storeLegacyFailure(address.addressString)
        }

        let geocoder = MockGeocoder.alwaysSucceeding()
        let result = run(
            makeManager(cache: cache, geocoder: geocoder),
            addresses: hits + legacyFailures + misses
        )

        #expect(result.summary?.resolvedFromCache == 30)
        #expect(result.summary?.retriedCachedFailures == 10)
        #expect(result.summary?.geocoded == 20, "10 legacy failures + 10 misses are geocoded")
        #expect(result.resolved.count == 50, "Nothing is silently lost")
        #expect(result.summary?.attempted == 50)
    }

    /// UC10: A burst of store-change notifications collapses into a single refresh.
    @Test func uc10_notificationStormCollapsesIntoOneRefresh() {
        let coalescer = ContactChangeCoalescer()

        for _ in 0..<5 {
            #expect(coalescer.noteChange() == .deferUntilInitialLoadCompletes)
        }

        #expect(coalescer.noteInitialLoadComplete(), "The burst yields exactly one refresh")
        #expect(coalescer.hasPendingChange == false)
        #expect(coalescer.noteInitialLoadComplete() == false, "Later completions must not re-trigger")
    }
}
