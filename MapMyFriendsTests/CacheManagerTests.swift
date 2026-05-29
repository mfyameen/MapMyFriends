//
//  CacheManagerTests.swift
//  MapMyFriendsTests
//

import Foundation
import Testing
@testable import MapMyFriends

struct CacheManagerTests {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    @Test func storeAndRetrieve() {
        let cache = CacheManager(fileURL: makeTempFileURL())
        let coord = CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date())

        cache.store(coordinate: coord, for: "123 Main St")
        let result = cache.coordinate(for: "123 Main St")

        #expect(result != nil)
        #expect(result?.lat == 37.0)
        #expect(result?.lng == -122.0)
    }

    @Test func cacheMissReturnsNil() {
        let cache = CacheManager(fileURL: makeTempFileURL())
        #expect(cache.coordinate(for: "nonexistent") == nil)
    }

    @Test func overwriteKeepsLatestValue() {
        let cache = CacheManager(fileURL: makeTempFileURL())
        cache.store(coordinate: CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date()), for: "addr")
        cache.store(coordinate: CachedCoordinate(lat: 2.0, lng: 2.0, cachedAt: Date()), for: "addr")

        let result = cache.coordinate(for: "addr")
        #expect(result?.lat == 2.0)
        #expect(result?.lng == 2.0)
    }

    @Test func saveAndReloadRoundTrip() {
        let url = makeTempFileURL()
        let cache1 = CacheManager(fileURL: url)
        cache1.store(coordinate: CachedCoordinate(lat: 10.0, lng: 20.0, cachedAt: Date()), for: "addr1")
        cache1.store(coordinate: CachedCoordinate(lat: 30.0, lng: 40.0, cachedAt: Date()), for: "addr2")
        cache1.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        #expect(cache2.coordinate(for: "addr1")?.lat == 10.0)
        #expect(cache2.coordinate(for: "addr2")?.lng == 40.0)
    }

    @Test func emptyFileOnFirstLoad() {
        let url = makeTempFileURL()
        // File does not exist yet
        let cache = CacheManager(fileURL: url)
        #expect(cache.coordinate(for: "anything") == nil)
    }

    @Test func corruptFileRecovery() throws {
        let url = makeTempFileURL()
        try Data("not valid json".utf8).write(to: url)

        let cache = CacheManager(fileURL: url)
        #expect(cache.coordinate(for: "anything") == nil)
    }

    @Test func multipleEntries() {
        let url = makeTempFileURL()
        let cache1 = CacheManager(fileURL: url)

        for i in 0..<100 {
            cache1.store(
                coordinate: CachedCoordinate(lat: Double(i), lng: Double(i) * -1, cachedAt: Date()),
                for: "address_\(i)"
            )
        }
        cache1.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        for i in 0..<100 {
            let result = cache2.coordinate(for: "address_\(i)")
            #expect(result?.lat == Double(i))
        }
    }

    // MARK: - TTL

    @Test func freshEntryReturnedWithinTTL() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 60)
        let coord = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())
        cache.store(coordinate: coord, for: "addr")
        #expect(cache.coordinate(for: "addr") != nil)
    }

    @Test func staleEntryReturnedAsNil() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 60)
        let staleDate = Date(timeIntervalSinceNow: -120) // 2 minutes ago, TTL is 60s
        let coord = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: staleDate)
        cache.store(coordinate: coord, for: "addr")
        #expect(cache.coordinate(for: "addr") == nil, "Stale entry should be treated as a miss")
    }

    @Test func zeroTTLRejectsEverything() {
        let cache = CacheManager(fileURL: makeTempFileURL(), ttl: 0)
        let coord = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())
        cache.store(coordinate: coord, for: "addr")
        #expect(cache.coordinate(for: "addr") == nil)
    }

    // MARK: - Failed Entries

    @Test func failedEntryPersistsAndReloads() {
        let url = makeTempFileURL()
        let cache1 = CacheManager(fileURL: url)
        cache1.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true), for: "bad_addr")
        cache1.saveToDisk()

        let cache2 = CacheManager(fileURL: url)
        let result = cache2.coordinate(for: "bad_addr")
        #expect(result != nil)
        #expect(result?.failed == true)
    }
}
