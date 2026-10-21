//
//  ManualGeocoder.swift
//  MapMyFriendsTests
//

import CoreLocation
import Foundation
@testable import MapMyFriends

/// Geocoder whose callbacks fire only when the test says so — models the real,
/// asynchronous `MapKitGeocoder`, including responses that arrive after a cancel.
final class ManualGeocoder: AddressGeocoding {

    private var pending: [(address: String, completion: (GeocodeOutcome) -> Void)] = []
    /// Every address handed to `geocode`, in call order.
    private(set) var requestedAddresses: [String] = []
    private(set) var cancelInFlightCallCount = 0

    var pendingAddresses: [String] { pending.map(\.address) }

    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void) {
        requestedAddresses.append(address)
        pending.append((address, completion))
    }

    func cancelInFlight() {
        // Like MKGeocodingRequest, cancelling does not stop a response already on its way.
        cancelInFlightCallCount += 1
    }

    /// Delivers `outcome` to the oldest pending request for `address`.
    func complete(_ address: String, with outcome: GeocodeOutcome) {
        guard let index = pending.firstIndex(where: { $0.address == address }) else { return }
        let request = pending.remove(at: index)
        request.completion(outcome)
    }

    func succeed(_ address: String, lat: Double = 37.0, lng: Double = -122.0) {
        complete(address, with: .success(CLLocationCoordinate2D(latitude: lat, longitude: lng)))
    }
}

/// Synchronous geocoder that plays back a scripted sequence of outcomes per address,
/// e.g. throttled twice and then successful.
final class ScriptedGeocoder: AddressGeocoding {

    private var scripts: [String: [GeocodeOutcome]] = [:]
    var fallback: GeocodeOutcome
    private(set) var requestedAddresses: [String] = []

    init(fallback: GeocodeOutcome = .success(CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))) {
        self.fallback = fallback
    }

    func script(_ address: String, _ outcomes: [GeocodeOutcome]) {
        scripts[address] = outcomes
    }

    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void) {
        requestedAddresses.append(address)
        if var queue = scripts[address], !queue.isEmpty {
            let next = queue.removeFirst()
            scripts[address] = queue
            completion(next)
        } else {
            completion(fallback)
        }
    }

    func cancelInFlight() {}
}
