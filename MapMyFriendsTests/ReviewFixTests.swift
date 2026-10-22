//
//  ReviewFixTests.swift
//  MapMyFriendsTests
//
//  Bugs found in the October 2026 code review, each written as a failing test first.
//

import Foundation
import Testing
@testable import MapMyFriends

private func makeTempFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func entry(_ lat: Double = 1) -> CachedCoordinate {
    CachedCoordinate(lat: lat, lng: lat, cachedAt: Date())
}

// MARK: - The map moving on its own

/// With location off, the map re-framed every contact after each contact edit and each
/// foreground retry, yanking it away from wherever the user had zoomed.
struct InitialCameraPolicyTests {

    @Test func framesContactsOnlyOnce() {
        var policy = InitialCameraPolicy()

        let first = policy.shouldFrameContacts()
        let second = policy.shouldFrameContacts()
        let third = policy.shouldFrameContacts()

        #expect(first, "The first load frames the contacts")
        #expect(!second, "Later loads must leave the map where the user put it")
        #expect(!third)
    }

    @Test func centersOnUserOnlyOnce() {
        var policy = InitialCameraPolicy()

        let first = policy.shouldCenterOnUser()
        let second = policy.shouldCenterOnUser()

        #expect(first)
        #expect(!second)
    }

    @Test func noContactFramingOnceCenteredOnUser() {
        var policy = InitialCameraPolicy()

        _ = policy.shouldCenterOnUser()
        let framed = policy.shouldFrameContacts()

        #expect(!framed, "The user's surroundings are the launch view")
    }

    @Test func userLocationArrivingLateStillCentersOnce() {
        // Unchanged behaviour: contacts are framed first, then the first location fix wins.
        var policy = InitialCameraPolicy()

        _ = policy.shouldFrameContacts()
        let centered = policy.shouldCenterOnUser()
        let framedAgain = policy.shouldFrameContacts()

        #expect(centered)
        #expect(!framedAgain)
    }
}

// MARK: - Where the cache lives

/// The cache (every contact address plus its coordinate) was in Documents, so it went into
/// iCloud backups and outlived deleting the app. Apple's storage guidelines say data the app
/// can recreate must not be backed up, and the privacy policy says deleting the app removes it.
struct CacheLocationTests {

    @Test func defaultCacheIsNotInDocuments() {
        let url = CacheManager.defaultFileURL()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        #expect(!url.path.hasPrefix(documents.path), "Documents is user-visible and backed up")
        #expect(url.path.contains("Application Support"))
    }

    @Test func savedCacheIsExcludedFromBackup() throws {
        let url = makeTempFileURL()
        let cache = CacheManager(fileURL: url)
        cache.store(coordinate: entry(), for: "addr")
        cache.saveToDisk()

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func legacyCacheIsMovedToTheNewLocation() throws {
        let legacyDir = try makeTempDirectory()
        let newDir = try makeTempDirectory()
        let legacyURL = legacyDir.appendingPathComponent("address_cache.json")
        let newURL = newDir.appendingPathComponent("Cache/address_cache.json")

        let old = CacheManager(fileURL: legacyURL)
        old.store(coordinate: entry(7), for: "kept")
        old.saveToDisk()

        CacheManager.migrateLegacyFile(from: legacyURL, to: newURL)

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path), "The backed-up copy must be gone")
        #expect(CacheManager(fileURL: newURL).coordinate(for: "kept")?.lat == 7, "Nothing should need re-geocoding")
    }

    @Test func migrationNeverOverwritesANewerCache() throws {
        let dir = try makeTempDirectory()
        let legacyURL = dir.appendingPathComponent("legacy.json")
        let newURL = dir.appendingPathComponent("new.json")

        let old = CacheManager(fileURL: legacyURL)
        old.store(coordinate: entry(1), for: "addr")
        old.saveToDisk()
        let current = CacheManager(fileURL: newURL)
        current.store(coordinate: entry(2), for: "addr")
        current.saveToDisk()

        CacheManager.migrateLegacyFile(from: legacyURL, to: newURL)

        #expect(CacheManager(fileURL: newURL).coordinate(for: "addr")?.lat == 2)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path), "The stale copy is still removed")
    }

    @Test func migrationWithNothingToMoveIsHarmless() throws {
        let dir = try makeTempDirectory()

        CacheManager.migrateLegacyFile(from: dir.appendingPathComponent("missing.json"), to: dir.appendingPathComponent("new.json"))

        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.json").path))
    }
}

// MARK: - Forgetting deleted contacts

/// Entries were never removed, so a deleted contact's address stayed on disk forever —
/// contradicting the privacy policy and growing the file without bound.
struct CachePruningTests {

    @Test func retainOnlyDropsAddressesNoLongerInContacts() {
        let cache = CacheManager(fileURL: makeTempFileURL())
        cache.store(coordinate: entry(), for: "still here")
        cache.store(coordinate: entry(), for: "deleted contact")

        cache.retainOnly(["still here"])

        #expect(cache.coordinate(for: "still here") != nil)
        #expect(cache.coordinate(for: "deleted contact") == nil)
    }

    @Test func prunedAddressesStayGoneAfterReload() {
        let url = makeTempFileURL()
        let cache = CacheManager(fileURL: url)
        cache.store(coordinate: entry(), for: "still here")
        cache.store(coordinate: entry(), for: "deleted contact")
        cache.saveToDisk()

        cache.retainOnly(["still here"])
        cache.saveToDisk()

        let reloaded = CacheManager(fileURL: url)
        #expect(reloaded.coordinate(for: "deleted contact") == nil)
        #expect(reloaded.coordinate(for: "still here") != nil)
    }

    @Test func pruningAlsoDropsExpiredEntries() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 1, failedTtl: 1)
        cache.store(coordinate: CachedCoordinate(lat: 1, lng: 1, cachedAt: .distantPast), for: "old address")

        cache.retainOnly([])

        #expect(cache.expiredCoordinate(for: "old address") == nil)
    }

    @Test func geocodingManagerForgetsAddressesMissingFromAFullFetch() {
        let cache = MockCacheManager()
        cache.storeSuccess("kept")
        cache.storeSuccess("gone")
        let manager = GeocodingRunner.makeManager(cache: cache, geocoder: MockGeocoder())

        manager.forgetAddresses(notIn: [ContactsManager.RawContactAddress(
            contactID: "1", fullName: "A", addressLabel: "Home", addressString: "kept",
            thumbnailImageData: nil, phoneNumber: nil
        )])

        #expect(cache.storage.keys.sorted() == ["kept"])
        #expect(cache.saveToDiskCallCount == 1, "The removal must reach disk")
    }
}
