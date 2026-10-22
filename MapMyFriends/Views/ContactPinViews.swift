//
//  ContactPinViews.swift
//  MapMyFriends
//

import MapKit

/// Registers the map's annotation views and picks one per annotation. Extracted from
/// `MapViewController` so the wiring is unit-testable against a real `MKMapView`.
enum ContactPinViews {

    static func register(on mapView: MKMapView) {
        mapView.register(
            ContactAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        mapView.register(
            ContactPhotoAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: ContactPhotoAnnotationView.reuseIdentifier
        )
        mapView.register(
            ClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
    }

    /// `nil` for the user's location, so MapKit draws its own blue dot.
    static func view(for annotation: any MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        if let cluster = annotation as? MKClusterAnnotation {
            // Single-member cluster — display as a regular contact pin instead
            if cluster.memberAnnotations.count == 1,
               let member = cluster.memberAnnotations.first as? ContactAnnotation {
                return contactView(for: member, in: mapView)
            }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                for: annotation
            )
        }

        if let contact = annotation as? ContactAnnotation {
            return contactView(for: contact, in: mapView)
        }

        return nil
    }

    /// The photo pin for contacts with a photo, the blue marker for everyone else.
    private static func contactView(for annotation: ContactAnnotation, in mapView: MKMapView) -> MKAnnotationView {
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: annotation.pinReuseIdentifier, for: annotation)
        view.annotation = annotation
        return view
    }
}
