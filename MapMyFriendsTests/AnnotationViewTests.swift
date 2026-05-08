//
//  AnnotationViewTests.swift
//  MapMyFriendsTests
//

import MapKit
import UIKit
import Testing
@testable import MapMyFriends

struct ContactAnnotationViewTests {

    @Test func clusteringIdentifier() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.clusteringIdentifier == "contact")
    }

    @Test func markerTintColor() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
        #expect(view.markerTintColor == .systemBlue)
    }

    // canShowCallout is set in init but MKMarkerAnnotationView resets it
    // outside of a live map view hierarchy — not reliably testable in isolation.

    @Test func glyphImageIsSet() {
        let view = ContactAnnotationView(annotation: nil, reuseIdentifier: nil)
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
