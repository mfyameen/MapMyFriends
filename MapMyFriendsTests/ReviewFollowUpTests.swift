//
//  ReviewFollowUpTests.swift
//  MapMyFriendsTests
//
//  Improvements from the October 2026 review that needed no product decision.
//  Each test was written to fail first.
//

import Contacts
import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import MapMyFriends

private func makeMapped(id: String, name: String, address: String = "1 Test St", photo: Data? = nil) -> MappedContact {
    MappedContact(
        contactID: id,
        fullName: name,
        addressLabel: "Home",
        addressString: address,
        coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        thumbnailImageData: photo,
        phoneNumber: nil
    )
}

private func makeAddress(_ address: String) -> ContactsManager.RawContactAddress {
    ContactsManager.RawContactAddress(
        contactID: address, fullName: "Contact", addressLabel: "Home",
        addressString: address, thumbnailImageData: nil, phoneNumber: nil
    )
}

// MARK: - Cluster list order

struct ClusterListOrderTests {

    @Test func listIsSortedByName() {
        let contacts = ["Zoe", "adam", "Mia"].enumerated().map { makeMapped(id: "\($0.offset)", name: $0.element) }

        let names = ClusterTapResolver.listOrder(contacts).map(\.fullName)

        #expect(names == ["adam", "Mia", "Zoe"], "Case shouldn't decide the order")
    }

    @Test func numbersSortTheWayPeopleRead() {
        let contacts = ["Worker10", "Worker2", "Worker1"].enumerated().map { makeMapped(id: "\($0.offset)", name: $0.element) }

        let names = ClusterTapResolver.listOrder(contacts).map(\.fullName)

        #expect(names == ["Worker1", "Worker2", "Worker10"])
    }

    @Test func sameNameIsOrderedByAddressSoTheListIsStable() {
        let contacts = [
            makeMapped(id: "1", name: "Sam", address: "9 Elm St"),
            makeMapped(id: "2", name: "Sam", address: "1 Oak St"),
        ]

        let addresses = ClusterTapResolver.listOrder(contacts).map(\.addressString)

        #expect(addresses == ["1 Oak St", "9 Elm St"])
    }
}

// MARK: - Photo pin image is drawn once

struct PhotoPinImageCachingTests {

    private func photoData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    @Test func annotationRendersItsPinOnce() {
        let annotation = ContactAnnotation(mappedContact: makeMapped(id: "1", name: "A", photo: photoData()))

        #expect(annotation.photoPinImage === annotation.photoPinImage, "Re-rendered on every access")
    }

    @Test func reusingAViewForTheSameContactDoesNotRedraw() {
        // MapKit reuses views constantly while panning; each redraw decoded and re-rendered the photo.
        let annotation = ContactAnnotation(mappedContact: makeMapped(id: "1", name: "A", photo: photoData()))
        let view = ContactPhotoAnnotationView(annotation: annotation, reuseIdentifier: ContactPhotoAnnotationView.reuseIdentifier)
        let first = view.image

        view.prepareForReuse()
        view.annotation = annotation

        #expect(view.image === first)
        #expect(view.image === annotation.photoPinImage)
    }
}

// MARK: - Remembering addresses Apple Maps can't find

struct NotFoundAddressTests {

    @Test func placemarkNotFoundIsItsOwnOutcome() {
        let outcome = MapKitGeocoder.outcome(coordinate: nil, error: MKError(.placemarkNotFound))

        guard case .notFound = outcome else {
            Issue.record("Expected .notFound, got \(outcome)")
            return
        }
    }

    @Test func serverFailureIsStillAPlainFailure() {
        // A network or server problem says nothing about the address; it must not be remembered.
        let outcome = MapKitGeocoder.outcome(coordinate: nil, error: MKError(.serverFailure))

        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
    }

    @Test func notFoundAddressIsRememberedAndNotPlotted() {
        let cache = MockCacheManager()
        let geocoder = MockGeocoder()
        geocoder.outcomes["nowhere"] = .notFound

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress("nowhere")])

        #expect(result.resolved.isEmpty)
        #expect(result.summary?.failed == 1)
        #expect(cache.storage["nowhere"]?.notFound == true)
    }

    @Test func rememberedNotFoundAddressIsNotRequestedAgain() {
        let cache = MockCacheManager()
        cache.storage["nowhere"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), notFound: true)
        let geocoder = MockGeocoder.alwaysSucceeding()

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress("nowhere")])

        #expect(geocoder.requestedAddresses.isEmpty, "Re-requested on every foreground before")
        #expect(result.resolved.isEmpty, "A not-found marker is not a location")
        #expect(result.summary?.failed == 1, "It's still unmapped")
        #expect(result.summary?.skippedNotFound == 1)
    }

    @Test func notFoundIsForgottenAfterItsTTL() {
        let cache = CacheManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), notFoundTtl: 1)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(timeIntervalSinceNow: -10), notFound: true), for: "nowhere")

        #expect(cache.coordinate(for: "nowhere") == nil, "Should be asked about again after a day")
    }

    @Test func freshNotFoundIsReturnedByTheCache() {
        let cache = CacheManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), notFoundTtl: 3600)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), notFound: true), for: "nowhere")

        #expect(cache.coordinate(for: "nowhere")?.notFound == true)
    }

    @Test func notFoundIsNeverAnExpiredFallbackLocation() {
        let cache = CacheManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), notFoundTtl: 1)
        cache.store(coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: .distantPast, notFound: true), for: "nowhere")

        #expect(cache.expiredCoordinate(for: "nowhere") == nil, "0,0 must never be shown as a pin")
    }

    @Test func notFoundDuringARefreshKeepsTheKnownLocation() {
        let cache = MockCacheManager()
        cache.storeExpired("moved?", lat: 5, lng: 6)
        let geocoder = MockGeocoder(defaultOutcome: .notFound)

        let result = GeocodingRunner.launch(cache: cache, geocoder: geocoder, addresses: [makeAddress("moved?")])

        #expect(result.resolved.first?.coordinate.latitude == 5, "The pin stays where it was")
        #expect(cache.storage["moved?"] == nil, "A not-found answer must not replace a known location")
    }

    @Test func oldCacheFilesDecodeWithoutTheNotFoundKey() throws {
        let json = #"{"lat": 1, "lng": 2, "cachedAt": 0}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CachedCoordinate.self, from: json)

        #expect(decoded.notFound == false)
    }
}

// MARK: - Names follow the user's Contacts settings

struct ContactNameFormattingTests {

    private let formatter = CNPostalAddressFormatter()

    @Test func familyNameFirstNamesKeepTheirOrder() {
        // Chinese, Japanese and Korean names are written family name first, with no space.
        let contact = CNMutableContact()
        contact.givenName = "太郎"
        contact.familyName = "山田"

        #expect(ContactsManager.displayName(for: contact) == "山田太郎")
    }

    @Test func middleNamesAndSuffixesAreIncluded() {
        let contact = CNMutableContact()
        contact.givenName = "Martin"
        contact.middleName = "Luther"
        contact.familyName = "King"
        contact.nameSuffix = "Jr."

        let name = ContactsManager.displayName(for: contact)

        #expect(name.contains("Luther"), "Middle name dropped: \(name)")
        #expect(name.contains("Jr."), "Suffix dropped: \(name)")
    }

    @Test func fetchKeysCoverTheFormatter() {
        // CNContactFormatter throws if any key it reads wasn't fetched. A contact built in a
        // test has every key, so this checks the descriptor is actually requested.
        let formatterKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        let request = CNContactFetchRequest(keysToFetch: ContactsManager.keysToFetch)

        #expect(request.keysToFetch.contains { $0.isEqual(formatterKeys) })
    }
}
