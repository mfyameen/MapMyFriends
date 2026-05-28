//
//  CachedCoordinate.swift
//  MapMyFriends
//

import Foundation

struct CachedCoordinate: Codable, Sendable {
    let lat: Double
    let lng: Double
    let cachedAt: Date
    /// `true` if geocoding failed for this address. Prevents retrying on every launch.
    /// The entry still expires via TTL, so it will be retried after 90 days.
    let failed: Bool

    init(lat: Double, lng: Double, cachedAt: Date, failed: Bool = false) {
        self.lat = lat
        self.lng = lng
        self.cachedAt = cachedAt
        self.failed = failed
    }

    // Decode gracefully from older cache files that don't have the `failed` key
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        cachedAt = try container.decode(Date.self, forKey: .cachedAt)
        failed = try container.decodeIfPresent(Bool.self, forKey: .failed) ?? false
    }
}
