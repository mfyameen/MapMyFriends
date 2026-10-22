//
//  MapDependencies.swift
//  MapMyFriends
//

import CoreLocation

/// Contact store access for `MapViewController`: `ContactsManager` in the app, a fake in tests.
protocol ContactFetching {
    func requestAccessAndFetch(completion: @escaping @MainActor @Sendable (ContactsManager.FetchResult) -> Void)
}

extension ContactsManager: ContactFetching {}

/// The parts of `CLLocationManager` that `MapViewController` uses, so tests can stand in for it.
protocol LocationProviding: AnyObject {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var location: CLLocation? { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: LocationProviding {}
