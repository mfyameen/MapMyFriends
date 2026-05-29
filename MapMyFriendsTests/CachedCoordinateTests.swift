//
//  CachedCoordinateTests.swift
//  MapMyFriendsTests
//

import Foundation
import Testing
@testable import MapMyFriends

struct CachedCoordinateTests {

    @Test func codableRoundTrip() throws {
        let original = CachedCoordinate(lat: 37.7749, lng: -122.4194, cachedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: data)

        #expect(decoded.lat == original.lat)
        #expect(decoded.lng == original.lng)
        #expect(decoded.cachedAt == original.cachedAt)
    }

    @Test func jsonStability() throws {
        let json = """
        {"lat":40.7128,"lng":-74.006,"cachedAt":0}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: data)

        #expect(decoded.lat == 40.7128)
        #expect(decoded.lng == -74.006)
        #expect(decoded.cachedAt == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func datePrecision() throws {
        let now = Date()
        let coord = CachedCoordinate(lat: 0, lng: 0, cachedAt: now)

        let data = try JSONEncoder().encode(coord)
        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: data)

        let diff = abs(decoded.cachedAt.timeIntervalSince(now))
        #expect(diff < 0.001, "Date should survive encoding with sub-millisecond precision")
    }

    // MARK: - Failed Field

    @Test func failedDefaultsToFalse() {
        let coord = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date())
        #expect(coord.failed == false)
    }

    @Test func failedTrueRoundTrip() throws {
        let original = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: data)
        #expect(decoded.failed == true)
    }

    @Test func backwardCompatWithoutFailedKey() throws {
        // Simulates a cache file written before the `failed` field was added
        let json = """
        {"lat":1.0,"lng":2.0,"cachedAt":0}
        """
        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: Data(json.utf8))
        #expect(decoded.failed == false, "Missing key should default to false")
    }
}
