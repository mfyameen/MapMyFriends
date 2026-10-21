//
//  MissingPinTests.swift
//  MapMyFriendsTests
//
//  Scenarios where a contact with an address silently never reaches the map, vanishes
//  from it, or shows stale details. Each test names the failure it guards against.
//

import Contacts
import CoreLocation
import Foundation
import MapKit
import Testing
@testable import MapMyFriends

// MARK: - Helpers

private func makeAddress(
    id: String = "1",
    name: String = "Test User",
    label: String = "Home",
    address: String = "123 Main St",
    phone: String? = nil
) -> ContactsManager.RawContactAddress {
    ContactsManager.RawContactAddress(
        contactID: id,
        fullName: name,
        addressLabel: label,
        addressString: address,
        thumbnailImageData: nil,
        phoneNumber: phone
    )
}

private func makeMapped(
    id: String = "1",
    name: String = "Test User",
    label: String = "Home",
    address: String = "123 Main St",
    phone: String? = nil
) -> MappedContact {
    MappedContact(
        contactID: id,
        fullName: name,
        addressLabel: label,
        addressString: address,
        coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2),
        thumbnailImageData: nil,
        phoneNumber: phone
    )
}

private func makePostalAddress(street: String = "1 Infinite Loop", city: String = "Cupertino") -> CNLabeledValue<CNPostalAddress> {
    let postal = CNMutablePostalAddress()
    postal.street = street
    postal.city = city
    return CNLabeledValue(label: CNLabelHome, value: postal)
}

private func makeTempFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
}

private struct EnumerationFailure: Error {}

// MARK: - Reading contacts

struct ContactExtractionTests {

    private let formatter = CNPostalAddressFormatter()

    @Test func companyOnlyContactIsMapped() {
        // Businesses (the dentist, a favorite restaurant) are usually saved with only a company name.
        let contact = CNMutableContact()
        contact.contactType = .organization
        contact.organizationName = "Acme Dental"
        contact.postalAddresses = [makePostalAddress()]

        let addresses = ContactsManager.rawAddresses(from: contact, formatter: formatter)

        #expect(addresses.count == 1, "A company-only contact with an address was silently dropped")
        #expect(addresses.first?.fullName == "Acme Dental")
    }

    @Test func nicknameOnlyContactIsMapped() {
        let contact = CNMutableContact()
        contact.nickname = "Grandma"
        contact.postalAddresses = [makePostalAddress()]

        let addresses = ContactsManager.rawAddresses(from: contact, formatter: formatter)

        #expect(addresses.count == 1, "A nickname-only contact with an address was silently dropped")
        #expect(addresses.first?.fullName == "Grandma")
    }

    @Test func personNameStillWinsOverCompany() {
        let contact = CNMutableContact()
        contact.givenName = "Jane"
        contact.familyName = "Doe"
        contact.organizationName = "Acme"
        contact.postalAddresses = [makePostalAddress()]

        let addresses = ContactsManager.rawAddresses(from: contact, formatter: formatter)

        #expect(addresses.first?.fullName == "Jane Doe")
    }

    @Test func contactWithNoNameAtAllIsStillMapped() {
        // Better an "Unnamed contact" pin than an address that never shows up.
        let contact = CNMutableContact()
        contact.postalAddresses = [makePostalAddress()]

        let addresses = ContactsManager.rawAddresses(from: contact, formatter: formatter)

        #expect(addresses.count == 1)
    }

    @Test func fetchKeysCoverEveryNameFieldThatIsRead() {
        // Reading a property that wasn't fetched throws CNPropertyNotFetchedException and crashes.
        let keys = Set(ContactsManager.keysToFetch.compactMap { $0 as? String })

        #expect(keys.contains(CNContactOrganizationNameKey))
        #expect(keys.contains(CNContactNicknameKey))
    }

    @Test func enumerationErrorIsNotReportedAsACompleteList() {
        // A partial list treated as complete makes a refresh diff the missing contacts off the map.
        let result = ContactsManager.collectAddresses { _, block in
            for name in ["A", "B"] {
                let contact = CNMutableContact()
                contact.givenName = name
                contact.postalAddresses = [makePostalAddress()]
                block(contact)
            }
            throw EnumerationFailure()
        }

        guard case .failed = result else {
            Issue.record("Expected .failed for an interrupted enumeration, got \(result)")
            return
        }
    }

    @Test func emptyStoreIsSuccessNotFailure() {
        let result = ContactsManager.collectAddresses { _, _ in }

        guard case .success(let addresses) = result else {
            Issue.record("An empty store is a real, successful result, got \(result)")
            return
        }
        #expect(addresses.isEmpty)
    }
}

// MARK: - Interpreting MapKit responses

struct GeocodeOutcomeMappingTests {

    @Test func throttlingIsRecognizedAsRateLimited() {
        let error = MKError(.loadingThrottled)

        let outcome = MapKitGeocoder.outcome(coordinate: nil, error: error)

        guard case .rateLimited = outcome else {
            Issue.record("Throttling must be retried, not reported as a failed address; got \(outcome)")
            return
        }
    }

    @Test func invalidCoordinateIsNotASuccess() {
        let outcome = MapKitGeocoder.outcome(coordinate: kCLLocationCoordinate2DInvalid, error: nil)

        if case .success = outcome {
            Issue.record("An invalid coordinate must not be plotted or cached")
        }
    }

    @Test func nanCoordinateIsNotASuccess() {
        let nan = CLLocationCoordinate2D(latitude: .nan, longitude: .nan)

        let outcome = MapKitGeocoder.outcome(coordinate: nan, error: nil)

        if case .success = outcome {
            Issue.record("A NaN coordinate must not be plotted or cached")
        }
    }

    @Test func validCoordinateIsASuccess() {
        let outcome = MapKitGeocoder.outcome(coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122), error: nil)

        guard case .success = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
    }
}

// MARK: - Geocoding pipeline

struct GeocodingResilienceTests {

    // Rate limiting

    @Test func rateLimitedAddressIsRetriedInTheSameRun() {
        // Apple throttles bulk geocoding. Without a retry, a first launch with hundreds of
        // contacts maps only the first few dozen and drops the rest until the next launch.
        let geocoder = ScriptedGeocoder()
        geocoder.script("a", [.rateLimited, .rateLimited])

        let result = GeocodingRunner.launch(
            cache: MockCacheManager(),
            geocoder: geocoder,
            addresses: [makeAddress(id: "a", address: "a"), makeAddress(id: "b", address: "b")]
        )

        #expect(Set(result.resolvedAddresses) == ["a", "b"])
        #expect(result.summary?.failed == 0)
        #expect(geocoder.requestedAddresses == ["a", "a", "a", "b"])
    }

    @Test func persistentRateLimitEventuallyGivesUpAndReportsFailure() {
        let geocoder = ScriptedGeocoder(fallback: .rateLimited)
        let cache = MockCacheManager()

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: [makeAddress(id: "a", address: "a")]
        )

        #expect(result.summary?.failed == 1, "The run must finish and report the failure")
        #expect(cache.storage.isEmpty, "A throttled address must never be cached")
        #expect(geocoder.requestedAddresses.count > 1, "It should have been retried at least once")
        #expect(geocoder.requestedAddresses.count < 20, "Retries must be bounded")
    }

    // Bad coordinates

    @Test func invalidCoordinateFromGeocoderIsNotPlottedOrCached() {
        let geocoder = MockGeocoder()
        geocoder.outcomes["a"] = .success(CLLocationCoordinate2D(latitude: .nan, longitude: .nan))
        let cache = MockCacheManager()

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress(address: "a")])

        #expect(result.resolved.isEmpty)
        #expect(cache.storage.isEmpty)
        #expect(result.summary?.failed == 1)
    }

    // Cancel and restart (contact refresh mid-run)

    @Test func lateResponseFromCancelledRunIsIgnored() {
        let geocoder = ManualGeocoder()
        let manager = GeocodingManager(cache: MockCacheManager(), geocoder: geocoder, requestDelay: 0, rateLimitBackoff: 0)
        var resolved: [String] = []
        var completions = 0
        manager.onContactResolved = { resolved.append($0.addressString) }
        manager.onComplete = { _ in completions += 1 }

        manager.process(addresses: [makeAddress(id: "a", address: "a"), makeAddress(id: "b", address: "b")])
        manager.cancel()
        manager.process(addresses: [makeAddress(id: "c", address: "c")])

        // The cancelled run's response arrives after the new run started.
        geocoder.succeed("a")
        geocoder.succeed("c")

        #expect(resolved == ["c"], "A stale response re-added a contact from the cancelled run")
        #expect(!geocoder.requestedAddresses.contains("b"), "The cancelled run kept walking its old list")
        #expect(completions == 1, "Only the current run should report completion")
    }

    @Test func pendingStepFromCancelledRunDoesNotResume() async throws {
        let geocoder = ManualGeocoder()
        let manager = GeocodingManager(cache: MockCacheManager(), geocoder: geocoder, requestDelay: 0.05, rateLimitBackoff: 0)
        var resolved: [String] = []
        manager.onContactResolved = { resolved.append($0.addressString) }

        manager.process(addresses: [makeAddress(id: "a", address: "a"), makeAddress(id: "b", address: "b")])
        geocoder.succeed("a") // schedules "b" after the request delay
        manager.cancel()
        manager.process(addresses: [makeAddress(id: "c", address: "c")])

        try await Task.sleep(for: .milliseconds(250))

        #expect(!geocoder.requestedAddresses.contains("b"), "The cancelled run resumed after its delay")
        #expect(geocoder.pendingAddresses == ["c"])
    }

    // Expired cache entries

    @Test func expiredEntryShowsPinImmediately() {
        // When every entry expires at once (all were cached on the same first launch),
        // re-geocoding them all is throttled; the pins must not vanish while that happens.
        let cache = MockCacheManager()
        cache.storeExpired("a", lat: 5, lng: 6)
        let geocoder = ManualGeocoder() // never answers

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress(address: "a")])

        #expect(result.resolvedAddresses == ["a"])
        #expect(result.resolved.first?.coordinate.latitude == 5)
    }

    @Test func expiredEntryKeepsPinWhenRefreshFails() {
        let cache = MockCacheManager()
        cache.storeExpired("a", lat: 5, lng: 6)
        let geocoder = MockGeocoder(defaultOutcome: .failed(reason: "offline"))

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress(address: "a")])

        #expect(result.resolvedAddresses == ["a"], "A known location was thrown away because a refresh failed")
    }

    @Test func expiredEntryIsRefreshedWithoutADuplicatePin() {
        let cache = MockCacheManager()
        cache.storeExpired("a", lat: 5, lng: 6)
        let geocoder = MockGeocoder.alwaysSucceeding(lat: 9, lng: 9)

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress(address: "a")])

        #expect(result.resolved.count == 1, "One contact address, one pin")
        #expect(geocoder.requestedAddresses == ["a"], "Expired entries are still refreshed")
        #expect(cache.storage["a"]?.lat == 9, "The refreshed coordinate is cached for next launch")
    }
}

// MARK: - Cache durability

struct CacheDurabilityTests {

    @Test func invalidCoordinateDoesNotBreakSavingEverythingElse() {
        // JSON can't encode NaN: one bad entry made every save fail, so nothing persisted.
        let url = makeTempFileURL()
        let cache = CacheManager(fileURL: url)
        cache.store(coordinate: CachedCoordinate(lat: 37, lng: -122, cachedAt: Date()), for: "good")
        cache.store(coordinate: CachedCoordinate(lat: .nan, lng: .nan, cachedAt: Date()), for: "bad")
        cache.saveToDisk()

        let reloaded = CacheManager(fileURL: url)

        #expect(reloaded.coordinate(for: "good") != nil)
        #expect(reloaded.coordinate(for: "bad") == nil)
    }

    @Test func unreadableCacheFileIsNotOverwrittenWithAnEmptyCache() throws {
        // e.g. the file is still locked by Data Protection when the app launches.
        let url = makeTempFileURL()
        let original = CacheManager(fileURL: url)
        original.store(coordinate: CachedCoordinate(lat: 1, lng: 1, cachedAt: Date()), for: "old")
        original.saveToDisk()

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let cache = CacheManager(fileURL: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        cache.store(coordinate: CachedCoordinate(lat: 2, lng: 2, cachedAt: Date()), for: "new")
        cache.saveToDisk()

        let reloaded = CacheManager(fileURL: url)
        #expect(reloaded.coordinate(for: "old") != nil, "Every previously cached location was wiped")
        #expect(reloaded.coordinate(for: "new") != nil)
    }

    @Test func unreadableCacheFileIsReadOnceItBecomesAvailable() throws {
        let url = makeTempFileURL()
        let original = CacheManager(fileURL: url)
        original.store(coordinate: CachedCoordinate(lat: 1, lng: 1, cachedAt: Date()), for: "old")
        original.saveToDisk()

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let cache = CacheManager(fileURL: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        #expect(cache.coordinate(for: "old") != nil, "A cache hit was missed because the first read failed")
    }
}

// MARK: - Live contact sync

struct ContactEditSyncTests {

    @Test func renamedContactIsReplaced() {
        let result = ContactDiffer.diff(
            newAddresses: [makeAddress(name: "Robert Smith")],
            existing: [makeMapped(name: "Bob Smith")]
        )

        #expect(result.toRemoveIndices == [0], "The pin kept showing the old name")
        #expect(result.toAdd.map(\.fullName) == ["Robert Smith"])
    }

    @Test func relabeledAddressIsReplaced() {
        let result = ContactDiffer.diff(
            newAddresses: [makeAddress(label: "Work")],
            existing: [makeMapped(label: "Home")]
        )

        #expect(result.toRemoveIndices == [0])
        #expect(result.toAdd.map(\.addressLabel) == ["Work"])
    }

    @Test func changedPhoneNumberIsReplaced() {
        // Otherwise Call / Message on the pin dials the old number.
        let result = ContactDiffer.diff(
            newAddresses: [makeAddress(phone: "+1 555 0100")],
            existing: [makeMapped(phone: "+1 555 0199")]
        )

        #expect(result.toRemoveIndices == [0])
        #expect(result.toAdd.count == 1)
    }

    @Test func unchangedContactIsLeftAlone() {
        let result = ContactDiffer.diff(
            newAddresses: [makeAddress(phone: "+1 555 0100")],
            existing: [makeMapped(phone: "+1 555 0100")]
        )

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.isEmpty)
    }
}

// MARK: - Cluster taps

struct ClusterTapTests {

    private let home = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)

    /// `count` coordinates spread `metersApart` east of `home`.
    private func spread(_ count: Int, metersApart: Double) -> [CLLocationCoordinate2D] {
        let degreesPerMeter = 1 / (111_320 * cos(home.latitude * .pi / 180))
        return (0..<count).map {
            CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude + Double($0) * metersApart * degreesPerMeter)
        }
    }

    @Test func moreThanTenContactsAtOneAddressAreListed() {
        // Zooming never separates identical coordinates, so these contacts were unreachable.
        let members = Array(repeating: home, count: 12)

        let action = ClusterTapResolver.action(members: members, clusterCoordinate: home, visibleSpan: 0.01)

        #expect(action == .showList)
    }

    @Test func neighborsAreListedOnceTheMapIsFullyZoomedIn() {
        // Townhouses ~20 m apart can stay clustered at maximum zoom.
        let members = spread(3, metersApart: 20)

        let action = ClusterTapResolver.action(members: members, clusterCoordinate: members[1], visibleSpan: 0.001)

        #expect(action == .showList)
    }

    @Test func neighborsZoomWhenThereIsRoomToZoom() {
        let members = spread(3, metersApart: 20)

        let action = ClusterTapResolver.action(members: members, clusterCoordinate: members[1], visibleSpan: 0.5)

        if case .showList = action {
            Issue.record("Zooming in would separate these pins")
        }
    }

    @Test func distantMembersZoom() {
        let members = spread(4, metersApart: 5_000)

        let action = ClusterTapResolver.action(members: members, clusterCoordinate: members[1], visibleSpan: 0.2)

        if case .showList = action {
            Issue.record("Zooming in would separate these pins")
        }
    }
}
