//
//  MapViewController.swift
//  MapMyFriends
//

import Contacts
import MapKit
import SwiftUI
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
    private var isRefreshing = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Map My Friends"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showAbout)
        )

        setupMapView()
        setupGeocodingCallbacks()
        setupLocationManager()
        observeContactChanges()
        loadContacts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.backgroundColor = .clear
        view.addSubview(trackingButton)
        NSLayoutConstraint.activate([
            trackingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            trackingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])

    }

    // MARK: - About

    @objc private func showAbout() {
        let aboutVC = UIHostingController(rootView: AboutView())
        aboutVC.modalPresentationStyle = .pageSheet
        present(aboutVC, animated: true)
    }

    // MARK: - Location

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Contact Change Observation

    private func observeContactChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contactStoreDidChange),
            name: .CNContactStoreDidChange,
            object: nil
        )
    }

    @objc private func contactStoreDidChange(_ notification: Notification) {
        guard !isRefreshing else { return }
        refreshContacts()
    }

    // MARK: - Contacts & Geocoding

    private func loadContacts() {
        contactsManager.requestAccessAndFetch { [weak self] rawAddresses in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rawAddresses.isEmpty {
                    self.showContactsAccessDeniedAlert()
                    return
                }
                self.geocodingManager.process(
                    addresses: rawAddresses,
                    userLocation: self.locationManager.location?.coordinate
                )
            }
        }
    }

    private func refreshContacts() {
        isRefreshing = true
        geocodingManager.cancel()

        contactsManager.requestAccessAndFetch { [weak self] rawAddresses in
            guard let self else { return }
            self.diffAndUpdate(newAddresses: rawAddresses)
            self.isRefreshing = false
        }
    }

    private func diffAndUpdate(newAddresses: [ContactsManager.RawContactAddress]) {
        let existingAnnotations = mapView.annotations.compactMap { $0 as? ContactAnnotation }
        let existingContacts = existingAnnotations.map { $0.mappedContact }

        let result = ContactDiffer.diff(newAddresses: newAddresses, existing: existingContacts)

        // Remove stale annotations
        let annotationsToRemove = result.toRemoveIndices.map { existingAnnotations[$0] }
        if !annotationsToRemove.isEmpty {
            mapView.removeAnnotations(annotationsToRemove)
        }

        // Geocode and add new addresses
        if !result.toAdd.isEmpty {
            geocodingManager.process(
                addresses: result.toAdd,
                userLocation: locationManager.location?.coordinate
            )
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

        geocodingManager.onComplete = { [weak self] failedCount in
            self?.hideProgressBanner()
            self?.centerOnAnnotationsIfNeeded()
            if failedCount > 0 {
                self?.showGeocodingFailureBanner(count: failedCount)
            }
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

    // MARK: - Failure Banner

    private func showGeocodingFailureBanner(count: Int) {
        let noun = count == 1 ? "address" : "addresses"
        let banner = UILabel()
        banner.text = "\(count) \(noun) could not be mapped"
        banner.font = .systemFont(ofSize: 13, weight: .medium)
        banner.textColor = .white
        banner.textAlignment = .center
        banner.backgroundColor = UIColor.systemOrange
        banner.layer.cornerRadius = 10
        banner.clipsToBounds = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.alpha = 0
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.heightAnchor.constraint(equalToConstant: 36),
            banner.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
        // Padding via content insets
        banner.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        UIView.animate(withDuration: 0.25) { banner.alpha = 1 }

        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            UIView.animate(withDuration: 0.25, animations: { banner.alpha = 0 }) { _ in
                banner.removeFromSuperview()
            }
        }
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
        if annotation is MKUserLocation { return nil }
        return nil
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation as? ContactAnnotation else { return }
        let contact = annotation.mappedContact

        guard let phone = contact.phoneNumber, !phone.isEmpty else {
            let alert = UIAlertController(
                title: contact.fullName,
                message: "No phone number available for this contact.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
            return
        }

        let digits = phone.filter { $0.isNumber || $0 == "+" }

        let sheet = UIAlertController(title: contact.fullName, message: phone, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Call", style: .default) { _ in
            if let url = URL(string: "tel:\(digits)") {
                UIApplication.shared.open(url)
            }
        })

        sheet.addAction(UIAlertAction(title: "Message", style: .default) { _ in
            if let url = URL(string: "sms:\(digits)") {
                UIApplication.shared.open(url)
            }
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad popover anchor
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = control
            popover.sourceRect = control.bounds
        }

        present(sheet, animated: true)
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
