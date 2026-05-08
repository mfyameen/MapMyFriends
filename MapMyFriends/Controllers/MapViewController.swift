//
//  MapViewController.swift
//  MapMyFriends
//

import MapKit
import UIKit

class MapViewController: UIViewController {

    // MARK: - Properties

    private let mapView = MKMapView()
    private let locationManager = CLLocationManager()
    private let contactsManager = ContactsManager()
    private let geocodingManager = GeocodingManager()

    private var progressBanner: UIView?
    private var progressLabel: UILabel?
    private var didCenterOnUser = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Map My Friends"

        setupMapView()
        setupGeocodingCallbacks()
        setupLocationManager()
        loadContacts()
    }

    // MARK: - Map Setup

    private func setupMapView() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        mapView.delegate = self
        mapView.showsUserLocation = true

        mapView.register(
            ContactAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        mapView.register(
            ClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
    }

    // MARK: - Location

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Contacts & Geocoding

    private func loadContacts() {
        contactsManager.requestAccessAndFetch { [weak self] rawAddresses in
            guard let self else { return }
            if rawAddresses.isEmpty {
                self.showContactsAccessDeniedAlert()
                return
            }
            self.geocodingManager.process(addresses: rawAddresses)
        }
    }

    private func setupGeocodingCallbacks() {
        geocodingManager.onContactResolved = { [weak self] mappedContact in
            let annotation = ContactAnnotation(mappedContact: mappedContact)
            self?.mapView.addAnnotation(annotation)
        }

        geocodingManager.onProgress = { [weak self] completed, total in
            self?.updateProgressBanner(completed: completed, total: total)
        }

        geocodingManager.onComplete = { [weak self] in
            self?.hideProgressBanner()
            self?.centerOnAnnotationsIfNeeded()
        }
    }

    // MARK: - Progress Banner

    private func showProgressBanner() {
        guard progressBanner == nil else { return }

        let banner = UIView()
        banner.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        banner.layer.cornerRadius = 12
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.15
        banner.layer.shadowRadius = 8
        banner.layer.shadowOffset = CGSize(width: 0, height: 2)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.alpha = 0

        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(label)
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.heightAnchor.constraint(equalToConstant: 44),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

        progressBanner = banner
        progressLabel = label

        UIView.animate(withDuration: 0.25) {
            banner.alpha = 1
        }
    }

    private func updateProgressBanner(completed: Int, total: Int) {
        if progressBanner == nil {
            showProgressBanner()
        }
        progressLabel?.text = "Mapping \(completed) of \(total) contacts…"
    }

    private func hideProgressBanner() {
        guard let banner = progressBanner else { return }
        UIView.animate(withDuration: 0.25, animations: {
            banner.alpha = 0
        }, completion: { _ in
            banner.removeFromSuperview()
            self.progressBanner = nil
            self.progressLabel = nil
        })
    }

    // MARK: - Map Centering

    private func centerOnAnnotationsIfNeeded() {
        guard !didCenterOnUser else { return }

        let annotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        guard !annotations.isEmpty else { return }

        let rect = annotations.reduce(MKMapRect.null) { rect, annotation in
            let point = MKMapPoint(annotation.coordinate)
            let annotationRect = MKMapRect(x: point.x - 1000, y: point.y - 1000, width: 2000, height: 2000)
            return rect.union(annotationRect)
        }

        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: true)
    }

    // MARK: - Alerts

    private func showContactsAccessDeniedAlert() {
        let alert = UIAlertController(
            title: "Contacts Access Required",
            message: "Please enable Contacts access in Settings to use Map My Friends.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
        // Return nil for user location — MapKit handles it
        // Returning nil for other annotations lets registered classes take over
        if annotation is MKUserLocation { return nil }
        return nil
    }
}

// MARK: - CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didCenterOnUser, let location = locations.first else { return }
        didCenterOnUser = true

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        mapView.setRegion(region, animated: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
