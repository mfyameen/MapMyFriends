//
//  ContactPlottingScaleTests.swift
//  MapMyFriendsTests
//
//  Exercises the contact → geocode → plot pipeline against the full 1000-contact
//  fixture (`Fixtures/contacts-1000.json`): all 50 US states plus DC and 65 cities
//  across 6 continents.
//
//  These are the tests that would have caught the original regression: at 1000
//  contacts, a single cached failure class silently removes hundreds of pins.
//

import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

struct ContactPlottingScaleTests {

    // MARK: - Fixture Integrity

    @Test func fixtureLoadsOneThousandUniqueContacts() throws {
        let contacts = try ContactFixtures.load()

        #expect(contacts.count == 1000)
        #expect(Set(contacts.map(\.contactID)).count == 1000, "Contact IDs must be unique")
        #expect(Set(contacts.map(\.addressString)).count == 1000, "Addresses must be unique")

        let coordinates = Set(contacts.map { "\($0.latitude),\($0.longitude)" })
        #expect(coordinates.count == 1000, "Coordinates must be unique so pins are distinguishable")

        for contact in contacts {
            #expect(!contact.addressString.isEmpty)
            #expect(contact.addressString.contains("\n"), "Addresses should be multi-line like CNPostalAddressFormatter output")
            #expect(contact.latitude >= -90 && contact.latitude <= 90)
            #expect(contact.longitude >= -180 && contact.longitude <= 180)
        }
    }

    @Test func fixtureSpansTheCountryAndTheWorld() {
        let contacts = ContactFixtures.all

        let usStates = Set(contacts.filter { $0.country == "United States" }.map(\.region))
        #expect(usStates.count == 51, "All 50 states plus DC should be represented")

        let countries = Set(contacts.map(\.country))
        #expect(countries.count >= 40, "Should span dozens of countries, got \(countries.count)")

        let international = contacts.filter { $0.country != "United States" }
        #expect(international.count >= 300, "A meaningful share of contacts should be outside the US")

        // Every inhabited continent, checked via latitude/longitude spread.
        #expect(contacts.contains { $0.latitude > 55 }, "Northern Europe / Alaska")
        #expect(contacts.contains { $0.latitude < -30 }, "Southern hemisphere")
        #expect(contacts.contains { $0.longitude > 100 }, "East Asia / Oceania")
        #expect(contacts.contains { $0.longitude < -140 }, "Hawaii / Alaska")
    }

    // MARK: - Cold Start

    @Test func coldStartPlotsAllOneThousandContacts() {
        let contacts = ContactFixtures.all
        let cache = MockCacheManager()
        let geocoder = ContactFixtures.geocoder(resolving: contacts)

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 1000, "Every contact should be plotted")
        #expect(result.summary?.geocoded == 1000)
        #expect(result.summary?.failed == 0)
        #expect(result.reportedFailureCount == 0)
        #expect(cache.storage.count == 1000, "Every success should be cached for the next launch")
        #expect(cache.storedFailureCount == 0)
    }

    @Test func coldStartPreservesEveryCoordinateExactly() {
        let contacts = ContactFixtures.all
        let geocoder = ContactFixtures.geocoder(resolving: contacts)

        let result = GeocodingRunner.launch(
            cache: MockCacheManager(),
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        let expected = Dictionary(uniqueKeysWithValues: contacts.map { ($0.addressString, $0.coordinate) })
        var mismatches: [String] = []
        for plotted in result.resolved {
            guard let want = expected[plotted.addressString] else {
                mismatches.append("unexpected address \(plotted.addressString)")
                continue
            }
            if plotted.coordinate.latitude != want.latitude || plotted.coordinate.longitude != want.longitude {
                mismatches.append(plotted.addressString)
            }
        }

        #expect(mismatches.isEmpty, "Coordinates must survive the pipeline unchanged: \(mismatches.prefix(5))")
    }

    @Test func progressIsReportedForEveryGeocodedAddress() {
        let contacts = ContactFixtures.first(400)
        let geocoder = ContactFixtures.geocoder(resolving: contacts)

        let result = GeocodingRunner.launch(
            cache: MockCacheManager(),
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.progressEvents.count == 400)
        #expect(result.progressEvents.first?.completed == 1)
        #expect(result.progressEvents.last?.completed == 400)
        #expect(result.progressEvents.allSatisfy { $0.total == 400 })
    }

    // MARK: - Warm Start

    @Test func warmStartPlotsAllOneThousandWithoutGeocoding() {
        let contacts = ContactFixtures.all
        let cache = ContactFixtures.warmCache(with: contacts)
        let geocoder = MockGeocoder()

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 1000)
        #expect(result.summary?.resolvedFromCache == 1000)
        #expect(result.summary?.geocoded == 0)
        #expect(geocoder.requestedAddresses.isEmpty, "A fully warm cache must not geocode anything")
        #expect(result.progressEvents.isEmpty, "No progress banner on a warm start")
    }

    @Test func warmStartWithNewContactsOnlyGeocodesTheNewOnes() {
        let contacts = ContactFixtures.all
        let known = Array(contacts.prefix(950))
        let added = Array(contacts.suffix(50))

        let cache = ContactFixtures.warmCache(with: known)
        let geocoder = ContactFixtures.geocoder(resolving: added)

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 1000)
        #expect(result.summary?.resolvedFromCache == 950)
        #expect(result.summary?.geocoded == 50)
        #expect(geocoder.requestedAddresses.count == 50)
    }

    // MARK: - Failure Recovery (the original regression, at scale)

    @Test func transientFailuresAreRetriedOnTheNextLaunch() {
        let contacts = ContactFixtures.all
        let cache = MockCacheManager()

        // Every 7th contact fails this launch — 143 of 1000.
        let failing = contacts.enumerated().filter { $0.offset % 7 == 0 }.map(\.element)
        let firstGeocoder = ContactFixtures.geocoder(resolving: contacts)
        for contact in failing {
            firstGeocoder.fail(contact.addressString, reason: "rate limited")
        }

        let firstLaunch = GeocodingRunner.launch(
            cache: cache,
            geocoder: firstGeocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(firstLaunch.resolved.count == 1000 - failing.count)
        #expect(firstLaunch.summary?.failed == failing.count)
        #expect(cache.storedFailureCount == 0, "Transient failures must never be cached")

        // Second launch, healthy network: the failures retry and everything appears.
        let secondGeocoder = ContactFixtures.geocoder(resolving: contacts)
        let secondLaunch = GeocodingRunner.launch(
            cache: cache,
            geocoder: secondGeocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(secondGeocoder.requestedAddresses.count == failing.count, "Only the failures retry")
        #expect(secondLaunch.resolved.count == 1000, "All 1000 contacts now plot")
        #expect(secondLaunch.summary?.failed == 0)
    }

    @Test func cacheFullOfLegacyFailuresRecoversEveryContact() {
        // Reproduces the reported bug at full scale: a cache written by the old build,
        // where every address is marked `failed: true`, used to plot zero pins.
        let contacts = ContactFixtures.all
        let cache = MockCacheManager()
        for contact in contacts {
            cache.storeLegacyFailure(contact.addressString)
        }
        let geocoder = ContactFixtures.geocoder(resolving: contacts)

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 1000, "Previously invisible contacts must all come back")
        #expect(result.summary?.retriedCachedFailures == 1000)
        #expect(result.summary?.resolvedFromCache == 0)
        #expect(cache.storedFailureCount == 0, "Successful retries replace the legacy failure entries")
    }

    @Test func totalGeocodeFailureCachesNothingAndRetriesEverything() {
        let contacts = ContactFixtures.first(500)
        let cache = MockCacheManager()
        let geocoder = MockGeocoder() // default outcome is failure

        let firstLaunch = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(firstLaunch.resolved.isEmpty)
        #expect(firstLaunch.summary?.failed == 500)
        #expect(firstLaunch.reportedFailureCount == 500, "The user-facing count must reflect all 500")
        #expect(cache.storage.isEmpty, "A total outage must leave the cache untouched")

        let recovered = ContactFixtures.geocoder(resolving: contacts)
        let secondLaunch = GeocodingRunner.launch(
            cache: cache,
            geocoder: recovered,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(secondLaunch.resolved.count == 500, "Every contact retries after an outage")
    }

    @Test func invalidAddressesAtScaleAreNeverCached() {
        let contacts = ContactFixtures.first(300)
        let cache = MockCacheManager()
        let geocoder = ContactFixtures.geocoder(resolving: contacts)

        let unparseable = Array(contacts.prefix(40))
        for contact in unparseable {
            geocoder.markInvalid(contact.addressString)
        }

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 260)
        #expect(result.summary?.invalidAddressStrings == 40)
        #expect(result.summary?.failed == 40)
        #expect(cache.storedFailureCount == 0)
        for contact in unparseable {
            #expect(cache.coordinate(for: contact.addressString) == nil)
        }
    }

    // MARK: - Mixed Cache State

    @Test func mixedCacheStateAtScaleLosesNothing() {
        let contacts = ContactFixtures.all
        let hits = Array(contacts[0..<700])
        let legacyFailures = Array(contacts[700..<850])
        let misses = Array(contacts[850..<1000])

        let cache = ContactFixtures.warmCache(with: hits)
        for contact in legacyFailures {
            cache.storeLegacyFailure(contact.addressString)
        }
        let geocoder = ContactFixtures.geocoder(resolving: legacyFailures + misses)

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: geocoder,
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.summary?.resolvedFromCache == 700)
        #expect(result.summary?.retriedCachedFailures == 150)
        #expect(result.summary?.geocoded == 300, "150 legacy failures + 150 misses")
        #expect(result.resolved.count == 1000)
        #expect(result.summary?.attempted == 1000)
        #expect(Set(result.resolvedAddresses).count == 1000, "No contact plotted twice")
    }

    // MARK: - Proximity Ordering

    @Test func warmCacheDeliversNearestFirstAcrossTheGlobe() {
        let contacts = ContactFixtures.all
        let cache = ContactFixtures.warmCache(with: contacts)
        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let result = GeocodingRunner.launch(
            cache: cache,
            geocoder: MockGeocoder(),
            addresses: ContactFixtures.rawAddresses(contacts),
            userLocation: sanFrancisco
        )

        #expect(result.resolved.count == 1000)

        let user = CLLocation(latitude: sanFrancisco.latitude, longitude: sanFrancisco.longitude)
        let distances = result.resolvedCoordinates.map {
            user.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }

        let outOfOrder = zip(distances, distances.dropFirst()).filter { $0 > $1 }.count
        #expect(outOfOrder == 0, "Pins must arrive nearest-first; \(outOfOrder) pairs out of order")

        // Sanity check the extremes: a Bay Area pin first, a far-flung one last.
        #expect((distances.first ?? .infinity) < 100_000, "Closest pin should be within ~100km")
        #expect((distances.last ?? 0) > 8_000_000, "Farthest pin should be thousands of km away")
    }

    // MARK: - Diffing At Scale

    @Test func deletedContactsAreDiffedOutAtScale() {
        let contacts = ContactFixtures.all
        let existing = contacts.map { contact in
            MappedContact(
                contactID: contact.contactID,
                fullName: contact.fullName,
                addressLabel: contact.addressLabel,
                addressString: contact.addressString,
                coordinate: contact.coordinate,
                thumbnailImageData: nil,
                phoneNumber: contact.phoneNumber
            )
        }

        // 100 contacts deleted from the address book between launches.
        let remaining = contacts.enumerated().filter { $0.offset % 10 != 0 }.map(\.element)
        let diff = ContactDiffer.diff(
            newAddresses: ContactFixtures.rawAddresses(remaining),
            existing: existing
        )

        #expect(diff.toRemoveIndices.count == 100)
        #expect(diff.toAdd.isEmpty)
    }

    @Test func newlyAddedContactsAreDiffedInAtScale() {
        let contacts = ContactFixtures.all
        let existing = contacts.prefix(900).map { contact in
            MappedContact(
                contactID: contact.contactID,
                fullName: contact.fullName,
                addressLabel: contact.addressLabel,
                addressString: contact.addressString,
                coordinate: contact.coordinate,
                thumbnailImageData: nil,
                phoneNumber: contact.phoneNumber
            )
        }

        let diff = ContactDiffer.diff(
            newAddresses: ContactFixtures.rawAddresses(contacts),
            existing: Array(existing)
        )

        #expect(diff.toAdd.count == 100)
        #expect(diff.toRemoveIndices.isEmpty)
    }

    // MARK: - Persistence At Scale

    @Test func oneThousandEntriesSurviveADiskRoundTrip() throws {
        let contacts = ContactFixtures.all
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let writer = CacheManager(fileURL: url)
        for contact in contacts {
            writer.store(
                coordinate: CachedCoordinate(lat: contact.latitude, lng: contact.longitude, cachedAt: Date()),
                for: contact.addressString
            )
        }
        writer.saveToDisk()

        let reader = CacheManager(fileURL: url)
        let result = GeocodingRunner.launch(
            cache: reader,
            geocoder: MockGeocoder(),
            addresses: ContactFixtures.rawAddresses(contacts)
        )

        #expect(result.resolved.count == 1000, "All 1000 cached entries should reload and plot")
        #expect(result.summary?.geocoded == 0)

        try? FileManager.default.removeItem(at: url)
    }
}
