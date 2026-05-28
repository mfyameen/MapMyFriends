//
//  ContactAnnotationView.swift
//  MapMyFriends
//

import MapKit
import UIKit

class ContactAnnotationView: MKMarkerAnnotationView {

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "contact"
        markerTintColor = .systemBlue
        glyphImage = UIImage(systemName: "person.fill")
        canShowCallout = true
        rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // TODO: Fix contact avatar display on pins — currently broken, disabled for now.
    // The applyAvatar() logic and circularImage() helper are preserved below for when this is revisited.
}
