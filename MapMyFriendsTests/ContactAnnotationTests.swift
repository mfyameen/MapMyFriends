//
//  ContactAnnotationTests.swift
//  MapMyFriendsTests
//

import CoreLocation
import Testing
@testable import MapMyFriends

struct ContactAnnotationTests {

    private let sampleContact = MappedContact(
        contactID: "abc-123",
        fullName: "Jane Doe",
        addressLabel: "Home",
        addressString: "123 Main St\nSan Francisco, CA",
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    )

    @Test func titleReturnsFullName() {
        let annotation = ContactAnnotation(mappedContact: sampleContact)
        #expect(annotation.title == "Jane Doe")
    }

    @Test func subtitleFormat() {
        let annotation = ContactAnnotation(mappedContact: sampleContact)
        #expect(annotation.subtitle == "Home · 123 Main St\nSan Francisco, CA")
    }

    @Test func coordinatePassthrough() {
        let annotation = ContactAnnotation(mappedContact: sampleContact)
        #expect(annotation.coordinate.latitude == 37.7749)
        #expect(annotation.coordinate.longitude == -122.4194)
    }
}
