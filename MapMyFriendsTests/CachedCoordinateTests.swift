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
}
