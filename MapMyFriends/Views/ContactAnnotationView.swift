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
        // TODO: Add rightCalloutAccessoryView for future deep-dive action
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var annotation: (any MKAnnotation)? {
        didSet { applyAvatar() }
    }

    // MARK: - Private

    private func applyAvatar() {
        guard
            let contactAnnotation = annotation as? ContactAnnotation,
            let data = contactAnnotation.mappedContact.thumbnailImageData,
            let image = UIImage(data: data)
        else {
            // No avatar — reset to default
            glyphImage = UIImage(systemName: "person.fill")
            markerTintColor = .systemBlue
            return
        }

        glyphImage = circularImage(from: image, size: CGSize(width: 40, height: 40))
        markerTintColor = .systemGray
    }

    private func circularImage(from source: UIImage, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()
            source.draw(in: rect)
        }
    }
}
