//
//  EdgeCaseTests.swift
//  MapMyFriendsTests
//
//  Edge cases from the second bug sweep (October 2026). Each test was written to fail first.
//

import Contacts
import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

private func makeAddress(_ street: String, id: String) -> ContactsManager.RawContactAddress {
    ContactsManager.RawContactAddress(
        contactID: id, fullName: "Contact \(id)", addressLabel: "work",
        addressString: street, thumbnailImageData: nil, phoneNumber: nil
    )
}

// MARK: - Addresses that aren't really addresses

struct IncompleteAddressTests {

    private let formatter = CNPostalAddressFormatter()

    private func contact(_ configure: (CNMutablePostalAddress) -> Void) -> CNContact {
        let postal = CNMutablePostalAddress()
        configure(postal)
        let contact = CNMutableContact()
        contact.givenName = "Pat"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal)]
        return contact
    }

    @Test func countryOnlyAddressIsNotMapped() {
        // iOS fills in the country as soon as you start an address. Geocoding "United States"
        // put this contact in the middle of Kansas.
        let pat = contact { $0.country = "United States"; $0.isoCountryCode = "us" }

        #expect(ContactsManager.rawAddresses(from: pat, formatter: formatter).isEmpty)
    }

    @Test func whitespaceOnlyFieldsDontCount() {
        let pat = contact { $0.street = "  "; $0.city = "\n"; $0.country = "Canada" }

        #expect(ContactsManager.rawAddresses(from: pat, formatter: formatter).isEmpty)
    }

    @Test func cityAndCountryIsStillMapped() {
        // A city-level pin is useful: it shows roughly where the person is.
        let pat = contact { $0.city = "Lisbon"; $0.country = "Portugal" }

        #expect(ContactsManager.rawAddresses(from: pat, formatter: formatter).count == 1)
    }

    @Test func postalCodeOnlyIsStillMapped() {
        let pat = contact { $0.postalCode = "94103" }

        #expect(ContactsManager.rawAddresses(from: pat, formatter: formatter).count == 1)
    }
}

// MARK: - Callout text

struct CalloutSubtitleTests {

    @Test func subtitleKeepsTheCityOnOneLine() {
        // Callouts show one line: everything after the first line break (city, state) was lost.
        let annotation = ContactAnnotation(mappedContact: MappedContact(
            contactID: "1", fullName: "Pat", addressLabel: "home",
            addressString: "10123 N Wolfe Rd\nCupertino CA 95014\nUnited States",
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            thumbnailImageData: nil, phoneNumber: nil
        ))

        #expect(annotation.subtitle == "home · 10123 N Wolfe Rd, Cupertino CA 95014, United States")
    }
}

// MARK: - One lookup per address

struct SharedAddressGeocodingTests {

    @Test func contactsSharingAnAddressAreGeocodedOnce() {
        // Twelve coworkers at one office cost twelve lookups against Apple's rate limit.
        let geocoder = MockGeocoder.alwaysSucceeding(lat: 37.33, lng: -122.01)
        let addresses = (1...12).map { makeAddress("1 Apple Park Way", id: "\($0)") }

        let result = GeocodingRunner.launch(cache: MockCacheManager(), geocoder: geocoder, addresses: addresses)

        #expect(geocoder.requestedAddresses == ["1 Apple Park Way"])
        #expect(result.resolved.count == 12, "Every coworker still gets a pin")
        #expect(Set(result.resolved.map(\.contactID)).count == 12)
        #expect(result.summary?.geocoded == 12)
    }

    @Test func aFailedSharedAddressReportsEveryContact() {
        let geocoder = MockGeocoder(defaultOutcome: .notFound)
        let addresses = (1...3).map { makeAddress("Nowhere", id: "\($0)") }

        let result = GeocodingRunner.launch(cache: MockCacheManager(), geocoder: geocoder, addresses: addresses)

        #expect(geocoder.requestedAddresses.count == 1)
        #expect(result.summary?.failed == 3)
        #expect(result.summary?.unmapped.count == 3)
    }

    @Test func progressCountsContactsNotLookups() {
        let addresses = (1...3).map { makeAddress("Same St", id: "\($0)") } + [makeAddress("Other St", id: "4")]

        let result = GeocodingRunner.launch(cache: MockCacheManager(), geocoder: MockGeocoder.alwaysSucceeding(), addresses: addresses)

        #expect(result.progressEvents.last?.total == 4, "\"Mapping N of M contacts\" counts contacts")
        #expect(result.progressEvents.last?.completed == 4)
    }
}

// MARK: - Saving the cache only when something changed

struct PruneSaveTests {

    @Test func forgettingNothingDoesNotRewriteTheCache() {
        let cache = MockCacheManager()
        cache.storeSuccess("kept")
        let manager = GeocodingRunner.makeManager(cache: cache, geocoder: MockGeocoder())

        manager.forgetAddresses(notIn: [makeAddress("kept", id: "1")])

        #expect(cache.saveToDiskCallCount == 0, "Every refresh rewrote the whole file")
    }

    @Test func realCacheReportsHowManyEntriesItDropped() {
        let cache = CacheManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        cache.store(coordinate: CachedCoordinate(lat: 1, lng: 1, cachedAt: Date()), for: "a")
        cache.store(coordinate: CachedCoordinate(lat: 1, lng: 1, cachedAt: Date()), for: "b")

        #expect(cache.retainOnly(["a"]) == 1)
        #expect(cache.retainOnly(["a"]) == 0)
    }
}

// MARK: - Call and Message links

struct PhoneDialerTests {

    @Test func formattedNumberDialsItsDigits() {
        #expect(PhoneDialer.callURL(for: "+1 (555) 010-0123")?.absoluteString == "tel:+15550100123")
    }

    @Test func extensionIsDialedAfterAPauseNotRunTogether() {
        // "555-1234 ext. 12" used to dial 555123412 — a different number.
        #expect(PhoneDialer.callURL(for: "555-1234 ext. 12")?.absoluteString == "tel:5551234,12")
        #expect(PhoneDialer.callURL(for: "(555) 123-4567 x89")?.absoluteString == "tel:5551234567,89")
        #expect(PhoneDialer.callURL(for: "555 123 4567;89")?.absoluteString == "tel:5551234567,89")
    }

    @Test func messagesGoToTheMainNumberOnly() {
        #expect(PhoneDialer.messageURL(for: "555-1234 ext. 12")?.absoluteString == "sms:5551234")
    }

    @Test func letterNumbersUseTheKeypad() {
        #expect(PhoneDialer.callURL(for: "1-800-FLOWERS")?.absoluteString == "tel:18003569377")
    }

    @Test func nonLatinDigitsAreConverted() {
        // Arabic-Indic digits passed `isNumber` but made a link no phone could dial.
        #expect(PhoneDialer.callURL(for: "٠١٢٣٤٥٦٧٨٩")?.absoluteString == "tel:0123456789")
    }

    @Test func plusOnlyCountsAtTheStart() {
        #expect(PhoneDialer.callURL(for: "555+1234")?.absoluteString == "tel:5551234")
    }

    @Test func numberWithNoDigitsHasNoLink() {
        #expect(PhoneDialer.callURL(for: "n/a") == nil, "Tapping Call did nothing at all")
        #expect(PhoneDialer.messageURL(for: "") == nil)
    }
}
