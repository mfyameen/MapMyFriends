//
//  MapViewController.swift
//  MapMyFriends
//

import Contacts
import ContactsUI
import MapKit
import SwiftUI
import UIKit

class MapViewController: UIViewController {

    // MARK: - Properties

    /// Contact store notifications are coalesced over this window so a burst of edits
    /// triggers a single refresh instead of one per notification.
    private static let contactChangeDebounceInterval: TimeInterval = 1.0

    private let mapView = MKMapView()
    private let locationManager = CLLocationManager()
    private let contactsManager = ContactsManager()
    private let geocodingManager = GeocodingManager()

    private var progressBanner: UIView?
    private var progressLabel: UILabel?
    private var didCenterOnUser = false
    private var isRefreshing = false
    /// Gates contact store changes until the initial geocoding pass has finished.
    private let contactChangeCoalescer = ContactChangeCoalescer()
    private var contactChangeDebounceWorkItem: DispatchWorkItem?

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
        contactChangeDebounceWorkItem?.cancel()
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
        switch contactChangeCoalescer.noteChange() {
        case .deferUntilInitialLoadCompletes:
            // Almost certainly the permission grant that kicked off the initial load.
            // It will be applied once that load has finished.
            break
        case .scheduleRefresh:
            scheduleContactRefresh()
        }
    }

    /// Coalesces rapid `CNContactStoreDidChange` bursts into a single refresh.
    private func scheduleContactRefresh() {
        contactChangeDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isRefreshing else {
                // A refresh is already in flight; retry after it settles so the change isn't lost.
                self.scheduleContactRefresh()
                return
            }
            self.refreshContacts()
        }

        contactChangeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.contactChangeDebounceInterval,
            execute: workItem
        )
    }

    // MARK: - Contacts & Geocoding

    private func loadContacts() {
        contactsManager.requestAccessAndFetch { [weak self] rawAddresses in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rawAddresses.isEmpty {
                    // No geocoding will run, so unblock refreshes explicitly.
                    if self.contactChangeCoalescer.noteInitialLoadComplete() {
                        self.scheduleContactRefresh()
                    }
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
        // An empty fetch means access was revoked or enumeration failed — not that every
        // contact was deleted. Diffing against it would remove every pin on the map.
        guard !newAddresses.isEmpty else {
            #if DEBUG
            print("[MapViewController] Contact fetch returned no addresses; keeping existing pins")
            #endif
            return
        }

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
            guard !FeatureFlags.hideGeocodingToasts else { return }
            self?.updateProgressBanner(completed: completed, total: total)
        }

        geocodingManager.onComplete = { [weak self] failedCount in
            guard let self else { return }
            self.hideProgressBanner()
            self.centerOnAnnotationsIfNeeded()
            if failedCount > 0, !FeatureFlags.hideGeocodingToasts {
                self.showGeocodingFailureBanner(count: failedCount)
            }

            // Apply any store change that arrived while the initial load was running.
            if self.contactChangeCoalescer.noteInitialLoadComplete() {
                self.scheduleContactRefresh()
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

        if let cluster = annotation as? MKClusterAnnotation {
            // Single-member cluster — display as a regular contact pin instead
            if cluster.memberAnnotations.count == 1,
               let member = cluster.memberAnnotations.first as? ContactAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                    for: member
                ) as? ContactAnnotationView
                view?.annotation = member
                return view
            }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                for: annotation
            )
        }

        if annotation is ContactAnnotation {
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                for: annotation
            )
            return view
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let cluster = view.annotation as? MKClusterAnnotation else { return }

        let members = cluster.memberAnnotations

        // Check if all members are at essentially the same point (can't be expanded by zooming)
        let allSameLocation = members.allSatisfy { member in
            let latDiff = abs(member.coordinate.latitude - cluster.coordinate.latitude)
            let lngDiff = abs(member.coordinate.longitude - cluster.coordinate.longitude)
            return latDiff < 0.0001 && lngDiff < 0.0001
        }

        if allSameLocation, members.count <= 10 {
            // Show a list of contacts at this location since zooming won't help
            mapView.deselectAnnotation(cluster, animated: false)
            let sheet = UIAlertController(
                title: "\(members.count) contacts at this location",
                message: nil,
                preferredStyle: .actionSheet
            )
            for member in members {
                if let contact = (member as? ContactAnnotation)?.mappedContact {
                    sheet.addAction(UIAlertAction(title: contact.fullName, style: .default) { [weak self] _ in
                        if FeatureFlags.openContactOnPinTap {
                            self?.openInContacts(contactID: contact.contactID)
                        }
                    })
                }
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
            present(sheet, animated: true)
            return
        }

        // Compute bounding rect of all members and zoom in with padding
        let rect = members.reduce(MKMapRect.null) { rect, member in
            let point = MKMapPoint(member.coordinate)
            let memberRect = MKMapRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200)
            return rect.union(memberRect)
        }

        let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)

        // Deselect so user can tap the same cluster again after it re-forms
        mapView.deselectAnnotation(cluster, animated: false)
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation as? ContactAnnotation else { return }
        let contact = annotation.mappedContact

        if FeatureFlags.openContactOnPinTap {
            openInContacts(contactID: contact.contactID)
        } else {
            showCallMessageSheet(for: contact, from: control)
        }
    }

    private func openInContacts(contactID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let cnContact = try CNContactStore().unifiedContact(
                    withIdentifier: contactID,
                    keysToFetch: [CNContactViewController.descriptorForRequiredKeys()]
                )
                DispatchQueue.main.async {
                    let contactVC = CNContactViewController(for: cnContact)
                    contactVC.allowsEditing = false
                    self?.navigationController?.pushViewController(contactVC, animated: true)
                }
            } catch {
                #if DEBUG
                print("[MapViewController] Failed to fetch contact: \(error)")
                #endif
            }
        }
    }

    private func showCallMessageSheet(for contact: MappedContact, from control: UIControl) {
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
