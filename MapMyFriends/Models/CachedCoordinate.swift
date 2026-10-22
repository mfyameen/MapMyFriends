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
    /// Apple Maps answered "no such place" for this address. Unlike a network failure that's
    /// a real answer, so it's remembered for `CacheManager.notFoundTTL` instead of being
    /// re-requested every time the app comes to the foreground. `lat`/`lng` are meaningless.
    let notFound: Bool

    init(lat: Double, lng: Double, cachedAt: Date, failed: Bool = false, notFound: Bool = false) {
        self.lat = lat
        self.lng = lng
        self.cachedAt = cachedAt
        self.failed = failed
        self.notFound = notFound
    }

    // Decode gracefully from older cache files that don't have the `failed` or `notFound` keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        cachedAt = try container.decode(Date.self, forKey: .cachedAt)
        failed = try container.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        notFound = try container.decodeIfPresent(Bool.self, forKey: .notFound) ?? false
    }
}
