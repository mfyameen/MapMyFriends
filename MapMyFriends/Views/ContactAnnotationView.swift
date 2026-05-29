//
//  ContactAnnotationView.swift
//  MapMyFriends
//

import MapKit
import UIKit

class ContactAnnotationView: MKMarkerAnnotationView {

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
        clusteringIdentifier = "contact"
        markerTintColor = .systemBlue
        glyphImage = UIImage(systemName: "person.fill")
        canShowCallout = true
        if rightCalloutAccessoryView == nil {
            rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        }
    }

    // TODO: Fix contact avatar display on pins — currently broken, disabled for now.
}
