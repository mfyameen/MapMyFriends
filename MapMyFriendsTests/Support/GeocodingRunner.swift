//
//  GeocodingRunner.swift
//  MapMyFriendsTests
//
//  Shared harness for driving `GeocodingManager` in tests.
//
//  Managers are built with `requestDelay: 0` and a synchronous `MockGeocoder`, so an
//  entire run — cache lookups, geocodes, progress, completion — finishes inside
//  `process()` with no network access and no waiting.
//

import CoreLocation
import Foundation
@testable import MapMyFriends

/// Everything a `GeocodingManager` reported during one `process()` call.
struct GeocodingRunResult {
    var resolved: [MappedContact] = []
    var progressEvents: [(completed: Int, total: Int)] = []
    var summary: GeocodingManager.Summary?
    var reportedFailureCount: Int?

    var resolvedAddresses: [String] { resolved.map(\.addressString) }
    var resolvedCoordinates: [CLLocationCoordinate2D] { resolved.map(\.coordinate) }
}

enum GeocodingRunner {

    static func makeManager(cache: CacheManaging, geocoder: AddressGeocoding) -> GeocodingManager {
        GeocodingManager(cache: cache, geocoder: geocoder, requestDelay: 0, rateLimitBackoff: 0, throttledRequestDelay: 0)
    }

    /// Runs `process()` to completion, capturing every callback.
    static func run(
        _ manager: GeocodingManager,
        addresses: [ContactsManager.RawContactAddress],
        userLocation: CLLocationCoordinate2D? = nil
    ) -> GeocodingRunResult {
        var result = GeocodingRunResult()
        manager.onContactResolved = { result.resolved.append($0) }
        manager.onProgress = { completed, total in result.progressEvents.append((completed, total)) }
        manager.onSummary = { result.summary = $0 }
        manager.onComplete = { result.reportedFailureCount = $0 }

        manager.process(addresses: addresses, userLocation: userLocation)
        return result
    }

    /// Builds a manager and runs it in one step — models a single app launch.
    static func launch(
        cache: CacheManaging,
        geocoder: AddressGeocoding,
        addresses: [ContactsManager.RawContactAddress],
        userLocation: CLLocationCoordinate2D? = nil
    ) -> GeocodingRunResult {
        run(makeManager(cache: cache, geocoder: geocoder), addresses: addresses, userLocation: userLocation)
    }
}
