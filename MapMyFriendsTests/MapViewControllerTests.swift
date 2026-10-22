//
//  MapViewControllerTests.swift
//  MapMyFriendsTests
//
//  The real `MapViewController`, driven with a fake contact store, a fake location manager
//  and a mock geocoder/cache: how it reacts to each kind of contact fetch, refreshes,
//  foreground retries, cache pruning and the first location fix.
//
//  Serialized: every controller listens to app-wide notifications, so two tests posting
//  them at once would trigger each other's refreshes.
//

import Contacts
import CoreLocation
import MapKit
import Testing
import UIKit
@testable import MapMyFriends

// MARK: - Fakes

/// Hands back scripted fetch results, one per call; the last one repeats.
private final class FakeContacts: ContactFetching {
    private var results: [ContactsManager.FetchResult]
    private let deliversLater: Bool
    private(set) var fetchCount = 0

    /// - Parameter deliversLater: Answer on a later main-queue turn, like the real store,
    ///   instead of before `requestAccessAndFetch` returns.
    init(_ results: [ContactsManager.FetchResult], deliversLater: Bool = false) {
        self.results = results
        self.deliversLater = deliversLater
    }

    func requestAccessAndFetch(completion: @escaping @MainActor @Sendable (ContactsManager.FetchResult) -> Void) {
        fetchCount += 1
        let result = results.count > 1 ? results.removeFirst() : results[0]
        if deliversLater {
            Task { @MainActor in completion(result) }
        } else {
            completion(result)
        }
    }
}

private final class FakeLocation: LocationProviding {
    weak var delegate: (any CLLocationManagerDelegate)?
    var location: CLLocation?
    private(set) var authorizationRequests = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestWhenInUseAuthorization() { authorizationRequests += 1 }
    func startUpdatingLocation() { startCount += 1 }
    func stopUpdatingLocation() { stopCount += 1 }
}

private func address(_ street: String) -> ContactsManager.RawContactAddress {
    ContactsManager.RawContactAddress(
        contactID: street, fullName: "Contact \(street)", addressLabel: "Home",
        addressString: street, thumbnailImageData: nil, phoneNumber: nil
    )
}

/// One app session: the controller plus everything it talks to.
private struct Session {
    let controller: MapViewController
    let contacts: FakeContacts
    let location: FakeLocation
    let cache: MockCacheManager
    let geocoder: MockGeocoder

    var pinnedAddresses: Set<String> {
        Set(controller.mapView.annotations.compactMap { ($0 as? ContactAnnotation)?.mappedContact.addressString })
    }

    init(
        fetches: [ContactsManager.FetchResult],
        cached: [String] = [],
        geocoder: MockGeocoder? = nil,
        deliversLater: Bool = false
    ) {
        cache = MockCacheManager()
        for street in cached { cache.storeSuccess(street) }
        // Built here, not as a default argument: those can't call main-actor code.
        let geocoder = geocoder ?? MockGeocoder.alwaysSucceeding()
        self.geocoder = geocoder
        contacts = FakeContacts(fetches, deliversLater: deliversLater)
        location = FakeLocation()
        controller = MapViewController(
            contacts: contacts,
            geocoding: GeocodingManager(cache: cache, geocoder: geocoder, requestDelay: 0, rateLimitBackoff: 0),
            location: location,
            contactChangeDebounceInterval: 0
        )
    }

    /// Runs `viewDidLoad`, which requests access and does the initial load.
    func launch() {
        controller.loadViewIfNeeded()
    }
}

/// Lets a zero-length debounce fire and the refresh it starts finish.
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(150))
}

// MARK: - Tests

@Suite(.serialized)
struct MapViewControllerTests {

    // Initial load

    @Test func initialLoadPlotsEveryContact() {
        let session = Session(fetches: [.success([address("a"), address("b")])], cached: ["a"])

        session.launch()

        #expect(session.pinnedAddresses == ["a", "b"])
    }

    @Test func initialLoadForgetsAddressesNoLongerInContacts() {
        let session = Session(fetches: [.success([address("a")])], cached: ["a", "deleted contact"])

        session.launch()

        #expect(session.cache.storage.keys.sorted() == ["a"])
    }

    @Test func deniedAccessShowsTheAlertAndKeepsTheCache() async throws {
        // The real store answers after the screen is up; an alert presented any earlier is dropped.
        let session = Session(fetches: [.denied], cached: ["a"], deliversLater: true)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = session.controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        session.launch()
        try await settle()

        let alert = session.controller.presentedViewController as? UIAlertController
        #expect(alert?.title == "Contacts Access Required")
        #expect(session.cache.storage.keys.sorted() == ["a"], "Denied access says nothing about what's in Contacts")
        #expect(session.pinnedAddresses.isEmpty)
    }

    @Test func failedInitialFetchKeepsTheCacheAndIsRetriedOnForeground() async throws {
        let session = Session(fetches: [.failed, .success([address("a")])], cached: ["a"])
        session.launch()
        #expect(session.cache.storage.keys.sorted() == ["a"], "A failed fetch must not prune")
        #expect(session.controller.hasUnmappedAddresses)

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await settle()

        #expect(session.contacts.fetchCount == 2)
        #expect(session.pinnedAddresses == ["a"])
    }

    // Refreshes

    @Test func refreshAfterAnEditRemovesDeletedContacts() async throws {
        let session = Session(fetches: [.success([address("a"), address("b")]), .success([address("a")])], cached: ["a", "b"])
        session.launch()

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()

        #expect(session.pinnedAddresses == ["a"])
        #expect(session.cache.storage.keys.sorted() == ["a"], "The deleted contact's address must leave the cache too")
    }

    @Test func refreshAddsNewContacts() async throws {
        let session = Session(fetches: [.success([address("a")]), .success([address("a"), address("new")])], cached: ["a"])
        session.launch()

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()

        #expect(session.pinnedAddresses == ["a", "new"])
    }

    @Test func failedRefreshKeepsEveryPinAndTheCache() async throws {
        let session = Session(fetches: [.success([address("a"), address("b")]), .failed], cached: ["a", "b"])
        session.launch()

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()

        #expect(session.pinnedAddresses == ["a", "b"], "Not knowing what's in Contacts is not the same as it being empty")
        #expect(session.cache.storage.keys.sorted() == ["a", "b"])
    }

    @Test func emptySuccessfulRefreshRemovesEveryPin() async throws {
        // Every contact with an address was deleted: a real, complete answer.
        let session = Session(fetches: [.success([address("a")]), .success([])], cached: ["a"])
        session.launch()

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()

        #expect(session.pinnedAddresses.isEmpty)
        #expect(session.cache.storage.isEmpty)
    }

    // Foreground retry

    @Test func foregroundDoesNothingWhenEveryContactIsMapped() async throws {
        let session = Session(fetches: [.success([address("a")])], cached: ["a"])
        session.launch()

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await settle()

        #expect(session.contacts.fetchCount == 1)
    }

    @Test func foregroundRetriesAddressesThatFailed() async throws {
        let geocoder = MockGeocoder.alwaysSucceeding()
        geocoder.fail("b", reason: "offline")
        let session = Session(fetches: [.success([address("a"), address("b")])], cached: ["a"], geocoder: geocoder)
        session.launch()
        #expect(session.pinnedAddresses == ["a"])

        geocoder.succeed("b")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await settle()

        #expect(session.contacts.fetchCount == 2)
        #expect(session.pinnedAddresses == ["a", "b"])
        #expect(!session.controller.hasUnmappedAddresses)
    }

    // Location

    @Test func asksForLocationAndListensForIt() {
        let session = Session(fetches: [.success([])])

        session.launch()

        #expect(session.location.authorizationRequests == 1)
        #expect(session.location.delegate === session.controller)
    }

    @Test func firstLocationFixStopsLocationUpdates() {
        let session = Session(fetches: [.success([])])
        session.launch()

        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 37.3, longitude: -122.0)])

        #expect(session.location.stopCount == 1, "GPS left running drains the battery")
    }

    @Test func firstLocationFixCentersTheMap() {
        let session = Session(fetches: [.success([])])
        session.launch()

        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 37.3, longitude: -122.0)])

        #expect(abs(session.controller.mapView.region.center.latitude - 37.3) < 0.5)
    }
}
