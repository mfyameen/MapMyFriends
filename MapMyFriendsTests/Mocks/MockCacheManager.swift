//
//  MockCacheManager.swift
//  MapMyFriendsTests
//

import Foundation
@testable import MapMyFriends

class MockCacheManager: CacheManaging {
    var storage: [String: CachedCoordinate] = [:]
    /// Successful entries past their TTL. `coordinate(for:)` treats these as misses.
    var expiredStorage: [String: CachedCoordinate] = [:]
    var saveToDiskCallCount = 0

    func coordinate(for address: String) -> CachedCoordinate? {
        storage[address]
    }

    func expiredCoordinate(for address: String) -> CachedCoordinate? {
        storage[address] == nil ? expiredStorage[address] : nil
    }

    func store(coordinate: CachedCoordinate, for address: String) {
        storage[address] = coordinate
    }

    @discardableResult
    func retainOnly(_ addresses: Set<String>) -> Int {
        let before = storage.count + expiredStorage.count
        storage = storage.filter { addresses.contains($0.key) }
        expiredStorage = expiredStorage.filter { addresses.contains($0.key) }
        return before - storage.count - expiredStorage.count
    }

    func saveToDisk() {
        saveToDiskCallCount += 1
    }

    // MARK: - Test Helpers

    /// Seeds a successful cache entry.
    func storeSuccess(_ address: String, lat: Double = 1.0, lng: Double = 2.0, cachedAt: Date = Date()) {
        storage[address] = CachedCoordinate(lat: lat, lng: lng, cachedAt: cachedAt)
    }

    /// Seeds a successful entry that has outlived its TTL.
    func storeExpired(_ address: String, lat: Double = 1.0, lng: Double = 2.0) {
        expiredStorage[address] = CachedCoordinate(lat: lat, lng: lng, cachedAt: .distantPast)
    }

    /// Seeds a legacy `failed: true` entry, as written by builds that cached geocoding failures.
    func storeLegacyFailure(_ address: String, cachedAt: Date = Date()) {
        storage[address] = CachedCoordinate(lat: 0, lng: 0, cachedAt: cachedAt, failed: true)
    }

    /// Number of entries flagged as failures. Should never grow once failure caching is removed.
    var storedFailureCount: Int {
        storage.values.filter(\.failed).count
    }
}
