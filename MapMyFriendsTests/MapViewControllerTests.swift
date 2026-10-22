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
    var hasLimitedAccess = false

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
        deliversLater: Bool = false,
        limitedAccess: Bool = false
    ) {
        cache = MockCacheManager()
        for street in cached { cache.storeSuccess(street) }
        // Built here, not as a default argument: those can't call main-actor code.
        let geocoder = geocoder ?? MockGeocoder.alwaysSucceeding()
        self.geocoder = geocoder
        contacts = FakeContacts(fetches, deliversLater: deliversLater)
        contacts.hasLimitedAccess = limitedAccess
        location = FakeLocation()
        controller = MapViewController(
            contacts: contacts,
            geocoding: GeocodingManager(cache: cache, geocoder: geocoder, requestDelay: 0, rateLimitBackoff: 0, throttledRequestDelay: 0),
            location: location,
            contactChangeDebounceInterval: 0
        )
    }

    /// Runs `viewDidLoad`, which requests access and does the initial load. The view gets a
    /// phone-sized frame: a zero-sized map ignores region changes, which would make every
    /// camera assertion pass by accident.
    func launch() {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        controller.view.layoutIfNeeded()
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

        // Far from the simulator's location, so the map can't already be there by chance.
        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: -45, longitude: 170)])

        let center = session.controller.mapView.region.center
        #expect(abs(center.latitude - -45) < 0.5 && abs(center.longitude - 170) < 0.5)
    }

    // Location is asked for after the pins appear (review decision #1)

    @Test func locationIsAskedForOnlyOnceThePinsAreOnTheMap() async throws {
        let session = Session(fetches: [.success([address("a")])], cached: ["a"], deliversLater: true)

        session.launch()
        #expect(session.location.authorizationRequests == 0, "Two permission prompts back to back at launch")

        try await settle()
        #expect(session.location.authorizationRequests == 1)
    }

    @Test func noLocationPromptWhenContactsAccessIsDenied() async throws {
        let session = Session(fetches: [.denied], deliversLater: true)

        session.launch()
        try await settle()

        #expect(session.location.authorizationRequests == 0, "Without contacts there's nothing to show nearby")
    }

    // The map stays where the user put it (review decision #8)

    @Test func movingTheMapBeforeTheFirstFixKeepsItThere() {
        let session = Session(fetches: [.success([])])
        session.launch()

        session.controller.userDidMoveMap()
        // A fix far from anywhere the map could already be showing.
        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: -45, longitude: 170)])

        let center = session.controller.mapView.region.center
        #expect(abs(center.latitude - -45) > 1 || abs(center.longitude - 170) > 1, "The map jumped to the user mid-pan")
        #expect(session.location.stopCount == 1, "Updates still stop after the first fix")
    }

    // Empty map card (review decision #2)

    @Test func noContactsWithAddressesShowsTheEmptyCard() {
        let session = Session(fetches: [.success([])])

        session.launch()

        #expect(session.controller.emptyState == .noAddresses(limitedAccess: false))
    }

    @Test func limitedAccessWithNothingSharedOffersToShareMore() {
        let session = Session(fetches: [.success([])], limitedAccess: true)

        session.launch()

        #expect(session.controller.emptyState == .noAddresses(limitedAccess: true))
    }

    @Test func contactsWithAddressesHideTheEmptyCard() {
        let session = Session(fetches: [.success([address("a")])], cached: ["a"])

        session.launch()

        #expect(session.controller.emptyState == nil)
    }

    @Test func emptyCardFollowsRefreshes() async throws {
        let session = Session(fetches: [.success([address("a")]), .success([]), .success([address("b")])], cached: ["a", "b"])
        session.launch()

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()
        #expect(session.controller.emptyState == .noAddresses(limitedAccess: false), "Last contact with an address deleted")

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()
        #expect(session.controller.emptyState == nil, "An address was added back")
    }

    @Test func failedFetchDoesNotClaimThereAreNoAddresses() {
        let session = Session(fetches: [.failed])

        session.launch()

        #expect(session.controller.emptyState == nil, "A failed fetch says nothing about what's in Contacts")
    }

    @Test func deniedAccessLeavesACardBehindAfterTheAlert() {
        // Once the alert was dismissed the map was blank forever, with nothing saying why.
        let session = Session(fetches: [.denied])

        session.launch()

        #expect(session.controller.emptyState == .accessDenied)
    }

    // Unmapped contacts button and list (review decision #3)

    @Test func unmappedContactsAreListedWithTheirReason() {
        let geocoder = MockGeocoder.alwaysSucceeding()
        geocoder.fail("offline")
        geocoder.outcomes["nowhere"] = .notFound
        let session = Session(fetches: [.success([address("a"), address("offline"), address("nowhere")])], cached: ["a"], geocoder: geocoder)

        session.launch()

        let reasons = Dictionary(uniqueKeysWithValues: session.controller.unmappedContacts.map { ($0.addressString, $0.reason) })
        #expect(reasons == ["offline": .couldNotConnect, "nowhere": .addressNotFound])
        #expect(session.controller.isShowingUnmappedButton)
    }

    @Test func everythingMappedHidesTheButton() {
        let session = Session(fetches: [.success([address("a")])], cached: ["a"])

        session.launch()

        #expect(session.controller.unmappedContacts.isEmpty)
        #expect(!session.controller.isShowingUnmappedButton)
    }

    @Test func aContactThatMapsOnRetryLeavesTheList() async throws {
        let geocoder = MockGeocoder.alwaysSucceeding()
        geocoder.fail("b")
        let session = Session(fetches: [.success([address("a"), address("b")])], cached: ["a"], geocoder: geocoder)
        session.launch()
        #expect(session.controller.unmappedContacts.map(\.addressString) == ["b"])

        geocoder.succeed("b")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await settle()

        #expect(session.controller.unmappedContacts.isEmpty)
        #expect(!session.controller.isShowingUnmappedButton)
    }

    @Test func aDeletedContactLeavesTheList() async throws {
        let geocoder = MockGeocoder.alwaysSucceeding()
        geocoder.outcomes["nowhere"] = .notFound
        let session = Session(fetches: [.success([address("a"), address("nowhere")]), .success([address("a")])], cached: ["a"], geocoder: geocoder)
        session.launch()
        #expect(session.controller.unmappedContacts.count == 1)

        NotificationCenter.default.post(name: .CNContactStoreDidChange, object: nil)
        try await settle()

        #expect(session.controller.unmappedContacts.isEmpty)
    }

    @Test func unmappedListIsSortedByName() {
        let geocoder = MockGeocoder(defaultOutcome: .notFound)
        let contacts = ["Zoe", "adam", "Mia"].map {
            ContactsManager.RawContactAddress(contactID: $0, fullName: $0, addressLabel: "Home", addressString: "\($0) St", thumbnailImageData: nil, phoneNumber: nil)
        }
        let session = Session(fetches: [.success(contacts)], geocoder: geocoder)

        session.launch()

        #expect(session.controller.unmappedContacts.map(\.fullName) == ["adam", "Mia", "Zoe"])
    }
    // Second bug sweep

    @Test func staleCachedFixIsNotTreatedAsTheUsersLocation() {
        // The first fix is often iOS's last known location — possibly yesterday, another city.
        let session = Session(fetches: [.success([])])
        session.launch()
        let stale = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -45, longitude: 170),
            altitude: 0, horizontalAccuracy: 50, verticalAccuracy: 50,
            timestamp: Date(timeIntervalSinceNow: -3600)
        )

        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [stale])

        let center = session.controller.mapView.region.center
        #expect(abs(center.latitude - -45) > 1, "Centered on an hour-old location")
        #expect(session.location.stopCount == 0, "Keep listening until a fresh fix arrives")
    }

    @Test func newestFixInABatchIsUsed() {
        // Core Location delivers oldest first; the last one is current.
        let session = Session(fetches: [.success([])])
        session.launch()
        let old = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10),
            altitude: 0, horizontalAccuracy: 50, verticalAccuracy: 50,
            timestamp: Date(timeIntervalSinceNow: -5)
        )
        let current = CLLocation(latitude: -45, longitude: 170)

        session.controller.locationManager(CLLocationManager(), didUpdateLocations: [old, current])

        let center = session.controller.mapView.region.center
        #expect(abs(center.latitude - -45) < 0.5 && abs(center.longitude - 170) < 0.5)
    }

    @Test func locationDeniedStopsUpdates() {
        let session = Session(fetches: [.success([])])
        session.launch()

        session.controller.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        #expect(session.location.stopCount == 1)
    }

    @Test func foregroundDoesNotRefetchJustForAddressesAppleCantFind() async throws {
        // A known-bad address is skipped without a lookup anyway; re-reading every contact on
        // every foreground to skip it again was wasted work.
        let geocoder = MockGeocoder.alwaysSucceeding()
        geocoder.outcomes["nowhere"] = .notFound
        let session = Session(fetches: [.success([address("a"), address("nowhere")])], cached: ["a"], geocoder: geocoder)
        session.launch()
        #expect(session.controller.isShowingUnmappedButton, "Still listed as not on the map")

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await settle()

        #expect(session.contacts.fetchCount == 1)
    }
}
