//
//  MockGeocoder.swift
//  MapMyFriendsTests
//

import CoreLocation
import Foundation
@testable import MapMyFriends

/// Deterministic, offline stand-in for `MapKitGeocoder`.
///
/// Completions fire synchronously, so a `GeocodingManager` built with `requestDelay: 0`
/// finishes an entire run inside `process()`.
final class MockGeocoder: AddressGeocoding {

    /// Per-address outcomes. Addresses with no entry fall back to `defaultOutcome`.
    var outcomes: [String: GeocodeOutcome] = [:]
    /// Outcome used for addresses with no explicit entry.
    var defaultOutcome: GeocodeOutcome = .failed(reason: "mock: no outcome configured")
    /// Every address handed to `geocode`, in call order.
    var requestedAddresses: [String] = []
    var cancelInFlightCallCount = 0

    init(defaultOutcome: GeocodeOutcome = .failed(reason: "mock: no outcome configured")) {
        self.defaultOutcome = defaultOutcome
    }

    /// Convenience: every address resolves to the same coordinate unless overridden.
    static func alwaysSucceeding(lat: Double = 37.0, lng: Double = -122.0) -> MockGeocoder {
        MockGeocoder(defaultOutcome: .success(CLLocationCoordinate2D(latitude: lat, longitude: lng)))
    }

    func succeed(_ address: String, lat: Double = 37.0, lng: Double = -122.0) {
        outcomes[address] = .success(CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    func fail(_ address: String, reason: String = "network error") {
        outcomes[address] = .failed(reason: reason)
    }

    func markInvalid(_ address: String) {
        outcomes[address] = .invalidAddress
    }

    // MARK: - AddressGeocoding

    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void) {
        requestedAddresses.append(address)
        completion(outcomes[address] ?? defaultOutcome)
    }

    func cancelInFlight() {
        cancelInFlightCallCount += 1
    }
}
