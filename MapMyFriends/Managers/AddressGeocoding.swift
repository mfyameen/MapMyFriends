//
//  AddressGeocoding.swift
//  MapMyFriends
//

import MapKit

/// Outcome of a single address geocode attempt.
enum GeocodeOutcome {
    /// The address resolved to a coordinate.
    case success(CLLocationCoordinate2D)
    /// The address string could not be turned into a geocoding request. No network call was
    /// made, so this is free to retry on the next launch and must never be cached as a failure.
    case invalidAddress
    /// A geocode was attempted but returned no usable result (network error, rate limit, no match).
    case failed(reason: String?)
}

/// Seam over MapKit geocoding so the contact-plotting pipeline can be exercised
/// deterministically in tests without touching the network.
@MainActor
protocol AddressGeocoding {
    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void)
    /// Cancels the request currently in flight, if any.
    func cancelInFlight()
}

/// Production implementation backed by `MKGeocodingRequest`.
@MainActor
final class MapKitGeocoder: AddressGeocoding {

    private var currentRequest: MKGeocodingRequest?

    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void) {
        guard let request = MKGeocodingRequest(addressString: address) else {
            completion(.invalidAddress)
            return
        }

        currentRequest = request

        request.getMapItems { mapItems, error in
            if let coordinate = mapItems?.first?.location.coordinate {
                completion(.success(coordinate))
            } else {
                completion(.failed(reason: error?.localizedDescription))
            }
        }
    }

    func cancelInFlight() {
        currentRequest?.cancel()
        currentRequest = nil
    }
}
