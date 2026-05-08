//
//  CacheIntegrationTests.swift
//  MapMyFriendsTests
//

import Foundation
import Testing
@testable import MapMyFriends

struct CacheIntegrationTests {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    @Test func writeKillRead() {
        let url = makeTempFileURL()

        // Write phase
        autoreleasepool {
            let cache = CacheManager(fileURL: url)
            cache.store(coordinate: CachedCoordinate(lat: 51.5074, lng: -0.1278, cachedAt: Date()), for: "London")
            cache.store(coordinate: CachedCoordinate(lat: 48.8566, lng: 2.3522, cachedAt: Date()), for: "Paris")
            cache.store(coordinate: CachedCoordinate(lat: 35.6762, lng: 139.6503, cachedAt: Date()), for: "Tokyo")
            cache.saveToDisk()
        }

        // Read phase — new instance from same file
        let cache2 = CacheManager(fileURL: url)
        #expect(cache2.coordinate(for: "London")?.lat == 51.5074)
        #expect(cache2.coordinate(for: "Paris")?.lng == 2.3522)
        #expect(cache2.coordinate(for: "Tokyo")?.lat == 35.6762)
        #expect(cache2.coordinate(for: "Berlin") == nil)
    }

    @Test func concurrentReadsDoNotCrash() {
        let url = makeTempFileURL()
        let cache = CacheManager(fileURL: url)

        for i in 0..<50 {
            cache.store(
                coordinate: CachedCoordinate(lat: Double(i), lng: Double(i), cachedAt: Date()),
                for: "addr_\(i)"
            )
        }
        cache.saveToDisk()

        // Read from multiple concurrent tasks — smoke test for crashes
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            let reader = CacheManager(fileURL: url)
            _ = reader.coordinate(for: "addr_\(i)")
        }
    }
}
