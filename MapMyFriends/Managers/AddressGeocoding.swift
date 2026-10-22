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
    /// A geocode was attempted but returned no usable result (network error, no match).
    case failed(reason: String?)
    /// Apple throttled the request. The address itself is fine and should be retried.
    case rateLimited
    /// Apple Maps has no place for this address. A real answer, unlike `.failed`, so it's
    /// remembered for a while rather than re-requested on every foreground.
    case notFound
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
            completion(Self.outcome(coordinate: mapItems?.first?.location.coordinate, error: error))
        }
    }

    /// Maps a MapKit geocoding response onto a `GeocodeOutcome`.
    nonisolated static func outcome(coordinate: CLLocationCoordinate2D?, error: Error?) -> GeocodeOutcome {
        if let coordinate {
            guard coordinate.isPlottable else {
                return .failed(reason: "invalid coordinate")
            }
            return .success(coordinate)
        }
        if let mapKitError = error as? MKError {
            switch mapKitError.code {
            case .loadingThrottled: return .rateLimited
            case .placemarkNotFound: return .notFound
            default: break
            }
        }
        return .failed(reason: error?.localizedDescription)
    }

    func cancelInFlight() {
        currentRequest?.cancel()
        currentRequest = nil
    }
}

extension CLLocationCoordinate2D {
    /// A real point on Earth: finite and within latitude/longitude bounds. Anything else
    /// can't be drawn on the map, and NaN can't even be written to the JSON cache.
    nonisolated var isPlottable: Bool {
        latitude.isFinite && longitude.isFinite && CLLocationCoordinate2DIsValid(self)
    }
}
