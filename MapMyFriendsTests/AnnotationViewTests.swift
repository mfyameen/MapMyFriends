//
//  AnnotationViewTests.swift
//  MapMyFriendsTests
//

import MapKit
import UIKit
import Testing
@testable import MapMyFriends

struct ContactAnnotationViewTests {

    private func makeContact(thumbnailImageData: Data? = nil) -> MappedContact {
        MappedContact(
            contactID: "test-id",
            fullName: "Test User",
            addressLabel: "Home",
            addressString: "1 Test St",
            coordinate: .init(latitude: 0, longitude: 0),
            thumbnailImageData: thumbnailImageData
        )
    }

    @Test func clusteringIdentifier() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.clusteringIdentifier == "contact")
    }

    @Test func markerTintColorDefaultBlue() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.markerTintColor == .systemBlue)
    }

    // canShowCallout is set in init but MKMarkerAnnotationView resets it
    // outside of a live map view hierarchy — not reliably testable in isolation.

    @Test func glyphImageIsSet() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.glyphImage != nil)
    }

    @Test func noAvatarKeepsDefaultGlyph() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        let annotation = ContactAnnotation(mappedContact: makeContact(thumbnailImageData: nil))
        view.annotation = annotation
        // Falls back to system icon — glyph should still be set
        #expect(view.glyphImage != nil)
        #expect(view.markerTintColor == .systemBlue)
    }

    @Test func validAvatarSwitchesMarkerToGray() {
        // Build a 1×1 red PNG as minimal valid image data
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let imageData = renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        let annotation = ContactAnnotation(mappedContact: makeContact(thumbnailImageData: imageData))
        view.annotation = annotation
        #expect(view.markerTintColor == .systemGray)
        #expect(view.glyphImage != nil)
    }

    @Test func invalidAvatarDataFallsBackToDefault() {
        let badData = Data([0x00, 0x01, 0x02]) // not a valid image
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        let annotation = ContactAnnotation(mappedContact: makeContact(thumbnailImageData: badData))
        view.annotation = annotation
        #expect(view.markerTintColor == .systemBlue)
        #expect(view.glyphImage != nil)
    }
}

struct ClusterAnnotationViewTests {

    @Test func frameSize() {
        let view = ClusterAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.frame.width == 40)
        #expect(view.frame.height == 40)
    }

    @Test func circleBackgroundColor() {
        let view = ClusterAnnotationView(annotation: nil, reuseIdentifier: nil)
        let circleView = view.subviews.first
        #expect(circleView?.backgroundColor == .systemBlue)
    }

    @Test func circleCornerRadius() {
        let view = ClusterAnnotationView(annotation: nil, reuseIdentifier: nil)
        let circleView = view.subviews.first
        #expect(circleView?.layer.cornerRadius == 20)
    }
}
