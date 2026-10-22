//
//  ReviewDecisionTests.swift
//  MapMyFriendsTests
//
//  Changes agreed after the October 2026 review: the map stays put once the user moves it,
//  lookups slow down once Apple throttles, every unmapped address is reported with a reason,
//  and pins and clusters read sensibly in VoiceOver. Each test was written to fail first.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import MapMyFriends

private func makeAddress(_ street: String, name: String = "Contact") -> ContactsManager.RawContactAddress {
    ContactsManager.RawContactAddress(
        contactID: "id-\(street)", fullName: name, addressLabel: "Home",
        addressString: street, thumbnailImageData: nil, phoneNumber: nil
    )
}

// MARK: - The map stays where the user put it

struct UserMovedMapPolicyTests {

    @Test func noCenteringOnUserOnceTheUserMovedTheMap() {
        // Location is now asked for after the pins appear, so the first fix often lands
        // while someone is already exploring.
        var policy = InitialCameraPolicy()

        policy.noteUserMovedMap()
        let centered = policy.shouldCenterOnUser()

        #expect(!centered)
    }

    @Test func noContactFramingOnceTheUserMovedTheMap() {
        var policy = InitialCameraPolicy()

        policy.noteUserMovedMap()
        let framed = policy.shouldFrameContacts()

        #expect(!framed)
    }

    @Test func untouchedMapStillCentersOnTheFirstFix() {
        var policy = InitialCameraPolicy()

        _ = policy.shouldFrameContacts()
        let centered = policy.shouldCenterOnUser()

        #expect(centered)
    }
}

// MARK: - Slowing down once Apple throttles

struct ThrottlePacingTests {

    /// Runs `process` and waits for `onComplete`, for runs that pause between lookups.
    private func runToCompletion(_ manager: GeocodingManager, _ addresses: [ContactsManager.RawContactAddress]) async -> [String] {
        var resolved: [String] = []
        manager.onContactResolved = { resolved.append($0.addressString) }
        await withCheckedContinuation { continuation in
            manager.onComplete = { _ in
                // One-shot: a later `process` on this manager must not resume it again.
                manager.onComplete = nil
                continuation.resume()
            }
            manager.process(addresses: addresses)
        }
        return resolved
    }

    @Test func throttlingSlowsTheRestOfTheRun() async {
        // Before: after a throttle, the next address went out at full speed and was throttled too.
        let geocoder = ScriptedGeocoder()
        geocoder.script("a", [.rateLimited])
        let manager = GeocodingManager(
            cache: MockCacheManager(), geocoder: geocoder,
            requestDelay: 0, rateLimitBackoff: 0, throttledRequestDelay: 0.01
        )

        let resolved = await runToCompletion(manager, [makeAddress("a"), makeAddress("b"), makeAddress("c")])

        #expect(manager.currentRequestDelay == 0.01, "Lookups after a throttle must use the slower pace")
        #expect(Set(resolved) == ["a", "b", "c"], "Slowing down must not lose anyone")
    }

    @Test func unthrottledRunKeepsItsPace() {
        let manager = GeocodingManager(
            cache: MockCacheManager(), geocoder: MockGeocoder.alwaysSucceeding(),
            requestDelay: 0, rateLimitBackoff: 0, throttledRequestDelay: 0.01
        )

        manager.process(addresses: [makeAddress("a"), makeAddress("b")])

        #expect(manager.currentRequestDelay == 0)
    }

    @Test func eachRunStartsFast() async {
        let geocoder = ScriptedGeocoder()
        geocoder.script("a", [.rateLimited])
        let manager = GeocodingManager(
            cache: MockCacheManager(), geocoder: geocoder,
            requestDelay: 0, rateLimitBackoff: 0, throttledRequestDelay: 0.01
        )
        _ = await runToCompletion(manager, [makeAddress("a"), makeAddress("b")])

        manager.process(addresses: [makeAddress("later")])

        #expect(manager.currentRequestDelay == 0, "A later run (contact edit, foreground) starts at full speed again")
    }
}

// MARK: - Reporting what isn't on the map

struct UnmappedReportTests {

    @Test func everyUnmappedAddressIsReportedWithItsReason() {
        let geocoder = ScriptedGeocoder()
        geocoder.script("nowhere", [.notFound])
        geocoder.script("offline", [.failed(reason: "network")])
        geocoder.script("garbled", [.invalidAddress])
        geocoder.script("throttled", Array(repeating: .rateLimited, count: 10))

        let result = GeocodingRunner.launch(
            cache: MockCacheManager(),
            geocoder: geocoder,
            addresses: ["nowhere", "offline", "garbled", "throttled", "fine"].map { makeAddress($0) }
        )

        let reasons = Dictionary(uniqueKeysWithValues: (result.summary?.unmapped ?? []).map { ($0.addressString, $0.reason) })
        #expect(reasons == [
            "nowhere": .addressNotFound,
            "offline": .couldNotConnect,
            "garbled": .addressNotFound,
            "throttled": .couldNotConnect,
        ])
    }

    @Test func rememberedNotFoundAddressesAreReportedToo() {
        let cache = MockCacheManager()
        cache.storage["nowhere"] = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), notFound: true)

        let result = GeocodingRunner.launch(cache: cache, geocoder: MockGeocoder(), addresses: [makeAddress("nowhere", name: "Pat")])

        #expect(result.summary?.unmapped == [UnmappedContact(
            contactID: "id-nowhere", fullName: "Pat", addressString: "nowhere", reason: .addressNotFound
        )])
    }

    @Test func refreshFailuresAreNotReportedBecauseThePinIsShowing() {
        let cache = MockCacheManager()
        cache.storeExpired("old")

        let result = GeocodingRunner.launch(cache: cache, geocoder: MockGeocoder(defaultOutcome: .failed(reason: "x")), addresses: [makeAddress("old")])

        #expect(result.summary?.unmapped.isEmpty == true)
    }
}

// MARK: - VoiceOver

struct VoiceOverLabelTests {

    private func makeAnnotation(name: String = "Jane Doe", photo: Bool = false) -> ContactAnnotation {
        var data: Data?
        if photo {
            data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { ctx in
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
        }
        return ContactAnnotation(mappedContact: MappedContact(
            contactID: name, fullName: name, addressLabel: "Home",
            addressString: "1 Infinite Loop\nCupertino CA 95014",
            coordinate: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
            thumbnailImageData: data, phoneNumber: nil
        ))
    }

    @Test func markerReadsNameLabelAndAddress() {
        let view = ContactAnnotationView(annotation: makeAnnotation(), reuseIdentifier: nil)

        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "Jane Doe, Home, 1 Infinite Loop, Cupertino CA 95014",
                "Line breaks in the address should read as pauses")
        #expect(view.accessibilityHint?.isEmpty == false)
    }

    @Test func photoPinReadsTheSameWay() {
        let view = ContactPhotoAnnotationView(annotation: makeAnnotation(photo: true), reuseIdentifier: ContactPhotoAnnotationView.reuseIdentifier)

        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "Jane Doe, Home, 1 Infinite Loop, Cupertino CA 95014")
    }

    @Test func photoPinNameIsNotReadTwice() {
        let view = ContactPhotoAnnotationView(annotation: makeAnnotation(photo: true), reuseIdentifier: ContactPhotoAnnotationView.reuseIdentifier)

        #expect(view.nameLabel.accessibilityElementsHidden || !view.nameLabel.isAccessibilityElement)
        #expect(view.accessibilityElements == nil || view.accessibilityElements?.isEmpty == true)
    }

    @Test func reusedPinReadsTheNewContact() {
        let view = ContactAnnotationView(annotation: makeAnnotation(name: "Jane Doe"), reuseIdentifier: nil)
        view.prepareForReuse()
        view.annotation = makeAnnotation(name: "John Roe")

        #expect(view.accessibilityLabel?.hasPrefix("John Roe") == true)
    }

    @Test func clusterReadsHowManyContacts() {
        let cluster = MKClusterAnnotation(memberAnnotations: [makeAnnotation(name: "A"), makeAnnotation(name: "B"), makeAnnotation(name: "C")])
        let view = ClusterAnnotationView(annotation: cluster, reuseIdentifier: nil)

        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "3 contacts")
        #expect(view.accessibilityHint?.isEmpty == false)
    }
}
