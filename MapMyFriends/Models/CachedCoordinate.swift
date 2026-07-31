//
//  CachedCoordinate.swift
//  MapMyFriends
//

import Foundation

struct CachedCoordinate: Codable, Sendable {
    let lat: Double
    let lng: Double
    let cachedAt: Date
    /// Legacy flag: older builds cached geocoding failures as `failed: true` to avoid retrying
    /// them every launch, which hid contacts behind transient failures. Failures are no longer
    /// written, but the field is retained so existing cache files still decode — and any entry
    /// with `failed == true` is now treated as a cache miss and retried.
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
