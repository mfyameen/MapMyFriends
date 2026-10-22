//
//  ContactAnnotationView.swift
//  MapMyFriends
//

import MapKit
import UIKit

class ContactAnnotationView: MKMarkerAnnotationView {

    /// Shared with `ContactPhotoAnnotationView` so photo pins and blue markers cluster together.
    static let contactClusteringIdentifier = "contact"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        applyDefaultStyle()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        applyDefaultStyle()
    }

    override var annotation: (any MKAnnotation)? {
        didSet {
            applyDefaultStyle()
        }
    }

    private func applyDefaultStyle() {
        clusteringIdentifier = Self.contactClusteringIdentifier
        markerTintColor = .systemBlue
        glyphImage = UIImage(systemName: "person.fill")
        canShowCallout = true
        if rightCalloutAccessoryView == nil {
            rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        }
        isAccessibilityElement = true
        accessibilityLabel = (annotation as? ContactAnnotation)?.accessibilityDescription
        accessibilityHint = "Double-tap to show details."
        accessibilityTraits = .button
    }
}
