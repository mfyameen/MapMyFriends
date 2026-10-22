//
//  PinWiringTests.swift
//  MapMyFriendsTests
//
//  The map's view registration and per-annotation view choice, run against a real
//  `MKMapView`. Without these, dropping a `register` call or the photo branch would
//  leave every other test green while photo pins quietly vanished from the app.
//

import CoreLocation
import MapKit
import Testing
import UIKit
@testable import MapMyFriends

struct PinWiringTests {

    private func makeMapView() -> MKMapView {
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        ContactPinViews.register(on: mapView)
        return mapView
    }

    private func makeAnnotation(id: String, withPhoto: Bool) -> ContactAnnotation {
        var photo: Data?
        if withPhoto {
            photo = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).pngData { ctx in
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            }
        }
        return ContactAnnotation(mappedContact: MappedContact(
            contactID: id,
            fullName: "Contact \(id)",
            addressLabel: "Home",
            addressString: "\(id) Test St",
            coordinate: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
            thumbnailImageData: photo,
            phoneNumber: nil
        ))
    }

    @Test func contactWithPhotoGetsThePhotoPin() {
        let mapView = makeMapView()
        let annotation = makeAnnotation(id: "1", withPhoto: true)

        let view = ContactPinViews.view(for: annotation, in: mapView)

        #expect(view is ContactPhotoAnnotationView)
        #expect(view?.annotation === annotation)
    }

    @Test func contactWithoutPhotoGetsTheBlueMarker() {
        let mapView = makeMapView()
        let annotation = makeAnnotation(id: "1", withPhoto: false)

        let view = ContactPinViews.view(for: annotation, in: mapView)

        #expect(view is ContactAnnotationView)
        #expect(view?.annotation === annotation)
    }

    @Test func singleMemberClusterShowsTheMembersPhotoPin() {
        let mapView = makeMapView()
        let member = makeAnnotation(id: "1", withPhoto: true)
        let cluster = MKClusterAnnotation(memberAnnotations: [member])

        let view = ContactPinViews.view(for: cluster, in: mapView)

        #expect(view is ContactPhotoAnnotationView, "A lone member must look like its own pin, not a cluster of 1")
        #expect(view?.annotation === member)
    }

    @Test func singleMemberClusterShowsTheMembersBlueMarker() {
        let mapView = makeMapView()
        let member = makeAnnotation(id: "1", withPhoto: false)

        let view = ContactPinViews.view(for: MKClusterAnnotation(memberAnnotations: [member]), in: mapView)

        #expect(view is ContactAnnotationView)
        #expect(view?.annotation === member)
    }

    @Test func multiMemberClusterGetsTheCountBubble() {
        let mapView = makeMapView()
        let cluster = MKClusterAnnotation(memberAnnotations: [
            makeAnnotation(id: "1", withPhoto: true),
            makeAnnotation(id: "2", withPhoto: false),
        ])

        let view = ContactPinViews.view(for: cluster, in: mapView)

        #expect(view is ClusterAnnotationView)
    }

    @Test func userLocationKeepsTheSystemBlueDot() {
        let mapView = makeMapView()

        #expect(ContactPinViews.view(for: mapView.userLocation, in: mapView) == nil)
    }
}
