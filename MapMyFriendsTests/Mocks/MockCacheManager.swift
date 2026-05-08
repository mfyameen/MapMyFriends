//
//  MockCacheManager.swift
//  MapMyFriendsTests
//

@testable import MapMyFriends

class MockCacheManager: CacheManaging {
    var storage: [String: CachedCoordinate] = [:]
    var saveToDiskCallCount = 0

    func coordinate(for address: String) -> CachedCoordinate? {
        storage[address]
    }

    func store(coordinate: CachedCoordinate, for address: String) {
        storage[address] = coordinate
    }

    func saveToDisk() {
        saveToDiskCallCount += 1
    }
}
