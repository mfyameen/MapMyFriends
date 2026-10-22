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
    private let contactChangeDebounceInterval: TimeInterval

    let mapView = MKMapView()
    private let locationManager: LocationProviding
    private let contactsManager: ContactFetching
    private let geocodingManager: GeocodingManager

    private var progressBanner: UIView?
    private var progressLabel: UILabel?
    /// Lets the map move on its own only for the launch view.
    private var camera = InitialCameraPolicy()
    private var isRefreshing = false
    /// Gates contact store changes until the initial geocoding pass has finished.
    private let contactChangeCoalescer = ContactChangeCoalescer()
    private var contactChangeDebounceWorkItem: DispatchWorkItem?
    /// Some contact addresses aren't on the map because a fetch or geocode failed this
    /// session. They're retried the next time the app comes to the foreground.
    private(set) var hasUnmappedAddresses = false

    // MARK: - Lifecycle

    /// Every dependency defaults to the real one; tests pass fakes. Defaults are built in the
    /// body because default-argument expressions can't touch main-actor state.
    init(
        contacts: ContactFetching? = nil,
        geocoding: GeocodingManager? = nil,
        location: LocationProviding? = nil,
        contactChangeDebounceInterval: TimeInterval = 1.0
    ) {
        self.contactsManager = contacts ?? ContactsManager()
        self.geocodingManager = geocoding ?? GeocodingManager()
        self.locationManager = location ?? CLLocationManager()
        self.contactChangeDebounceInterval = contactChangeDebounceInterval
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

        ContactPinViews.register(on: mapView)

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    /// Failed geocodes otherwise wait for a relaunch or a contact edit. A refresh diffs them
    /// back in (they have no pin), and successful ones are cached so this is cheap.
    @objc private func appWillEnterForeground(_ notification: Notification) {
        guard hasUnmappedAddresses else { return }
        contactStoreDidChange(notification)
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
            deadline: .now() + contactChangeDebounceInterval,
            execute: workItem
        )
    }

    // MARK: - Contacts & Geocoding

    private func loadContacts() {
        contactsManager.requestAccessAndFetch { [weak self] result in
            guard let self else { return }
            if case .success(let allAddresses) = result {
                self.geocodingManager.forgetAddresses(notIn: allAddresses)
            }
            guard case .success(let rawAddresses) = result, !rawAddresses.isEmpty else {
                if case .denied = result {
                    self.showContactsAccessDeniedAlert()
                } else if case .failed = result {
                    self.hasUnmappedAddresses = true
                }
                // No geocoding will run, so unblock refreshes explicitly.
                if self.contactChangeCoalescer.noteInitialLoadComplete() {
                    self.scheduleContactRefresh()
                }
                return
            }
            self.geocodingManager.process(
                addresses: rawAddresses,
                userLocation: self.locationManager.location?.coordinate
            )
        }
    }

    private func refreshContacts() {
        isRefreshing = true
        geocodingManager.cancel()

        contactsManager.requestAccessAndFetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let rawAddresses):
                self.geocodingManager.forgetAddresses(notIn: rawAddresses)
                self.diffAndUpdate(newAddresses: rawAddresses)
            case .denied, .failed:
                // Not knowing what's in the store is not the same as it being empty:
                // leave every pin alone and try again later.
                self.hasUnmappedAddresses = true
            }
            self.isRefreshing = false
        }
    }

    /// - Parameter newAddresses: A complete, successful fetch. Revoked access and failed
    ///   enumerations never get here, so an empty list really means no contact has an address.
    private func diffAndUpdate(newAddresses: [ContactsManager.RawContactAddress]) {
        hasUnmappedAddresses = false

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
            if failedCount > 0 {
                self.hasUnmappedAddresses = true
            }
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
        let label = UILabel()
        label.text = "\(count) \(noun) could not be mapped"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        // A UILabel ignores layoutMargins, so the padding comes from a container.
        let banner = UIView()
        banner.backgroundColor = UIColor.systemOrange
        banner.layer.cornerRadius = 10
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.alpha = 0
        banner.addSubview(label)
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])

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
        let annotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        guard !annotations.isEmpty, camera.shouldFrameContacts() else { return }

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
        ContactPinViews.view(for: annotation, in: mapView)
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let cluster = view.annotation as? MKClusterAnnotation else { return }

        let members = cluster.memberAnnotations
        let action = ClusterTapResolver.action(
            members: members.map(\.coordinate),
            clusterCoordinate: cluster.coordinate,
            visibleSpan: mapView.region.span.latitudeDelta
        )

        switch action {
        case .showList:
            // Zooming won't separate these pins, so list them instead
            mapView.deselectAnnotation(cluster, animated: false)
            let sheet = UIAlertController(
                title: "\(members.count) contacts here",
                message: nil,
                preferredStyle: .actionSheet
            )
            let contacts = ClusterTapResolver.listOrder(members.compactMap { ($0 as? ContactAnnotation)?.mappedContact })
            for contact in contacts {
                sheet.addAction(UIAlertAction(title: contact.fullName, style: .default) { [weak self] _ in
                    // Same behavior as tapping a single pin's info button.
                    if FeatureFlags.openContactOnPinTap {
                        self?.openInContacts(contactID: contact.contactID)
                    } else {
                        self?.showCallMessageSheet(for: contact, from: view)
                    }
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
            present(sheet, animated: true)

        case .zoom(let rect):
            let padding = UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

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

    private func showCallMessageSheet(for contact: MappedContact, from sourceView: UIView) {
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
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }

        present(sheet, animated: true)
    }
}

// MARK: - CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        // One fix is all this manager is for: the launch view and sorting nearby contacts
        // first (via `locationManager.location`). The map tracks the blue dot on its own, so leaving
        // GPS running would only drain the battery.
        locationManager.stopUpdatingLocation()
        guard camera.shouldCenterOnUser() else { return }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        mapView.setRegion(region, animated: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }
}
