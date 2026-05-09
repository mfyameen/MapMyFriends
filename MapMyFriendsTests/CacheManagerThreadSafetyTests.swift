//
//  CacheManagerThreadSafetyTests.swift
//  MapMyFriendsTests
//

import Foundation
import Testing
@testable import MapMyFriends

struct CacheManagerThreadSafetyTests {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    @Test func concurrentWritesDoNotCrash() {
        let cache = CacheManager(fileURL: makeTempFileURL())

        // Hammer the cache from multiple threads simultaneously
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let coord = CachedCoordinate(lat: Double(i), lng: Double(i), cachedAt: Date())
            cache.store(coordinate: coord, for: "addr_\(i)")
        }

        // Verify at least some entries persisted (exact count depends on timing)
        var found = 0
        for i in 0..<200 {
            if cache.coordinate(for: "addr_\(i)") != nil { found += 1 }
        }
        #expect(found == 200, "All concurrent writes should succeed")
    }

    @Test func concurrentReadsAndWritesDoNotCrash() {
        let cache = CacheManager(fileURL: makeTempFileURL())

        // Pre-populate some entries
        for i in 0..<50 {
            cache.store(coordinate: CachedCoordinate(lat: Double(i), lng: Double(i), cachedAt: Date()), for: "addr_\(i)")
        }

        // Concurrent mix of reads and writes
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            if i % 2 == 0 {
                // Write
                let coord = CachedCoordinate(lat: Double(i), lng: Double(i), cachedAt: Date())
                cache.store(coordinate: coord, for: "addr_\(i)")
            } else {
                // Read
                _ = cache.coordinate(for: "addr_\(i % 50)")
            }
        }

        // If we get here without a crash, the queue serialization is working
    }

    @Test func concurrentSaveToDiskDoesNotCrash() {
        let cache = CacheManager(fileURL: makeTempFileURL())

        for i in 0..<50 {
            cache.store(coordinate: CachedCoordinate(lat: Double(i), lng: Double(i), cachedAt: Date()), for: "addr_\(i)")
        }

        // Multiple concurrent saves — the snapshot approach should prevent corruption
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            cache.saveToDisk()
        }
    }

    @Test func writesDuringSaveAreNotLost() {
        let url = makeTempFileURL()
        let cache = CacheManager(fileURL: url)

        // Store, save, then store more before reloading
        cache.store(coordinate: CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date()), for: "first")
        cache.saveToDisk()
        cache.store(coordinate: CachedCoordinate(lat: 2.0, lng: 2.0, cachedAt: Date()), for: "second")
        cache.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        #expect(cache2.coordinate(for: "first")?.lat == 1.0)
        #expect(cache2.coordinate(for: "second")?.lat == 2.0)
    }
}
