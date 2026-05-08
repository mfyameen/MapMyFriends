//
//  ContactAnnotationView.swift
//  MapMyFriends
//

import MapKit

class ContactAnnotationView: MKMarkerAnnotationView {

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "contact"
        markerTintColor = .systemBlue
        glyphImage = UIImage(systemName: "person.fill")
        canShowCallout = true
        // TODO: Add rightCalloutAccessoryView for future deep-dive action
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
