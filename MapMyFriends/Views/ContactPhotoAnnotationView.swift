//
//  ContactPhotoAnnotationView.swift
//  MapMyFriends
//

import MapKit
import UIKit

/// Pin for contacts that have a photo: the photo in a white ring above a small pointer.
///
/// `MKMarkerAnnotationView` can't show a photo — it renders `glyphImage` as a one-colour
/// template, so a photo comes out as a plain white disc. This view draws its own image instead.
class ContactPhotoAnnotationView: MKAnnotationView {

    static let reuseIdentifier = "ContactPhoto"

    private static let photoDiameter: CGFloat = 40
    private static let borderWidth: CGFloat = 3
    private static let pointerHeight: CGFloat = 8
    private static let pointerHalfWidth: CGFloat = 6

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        applyStyle()
    }

    override var annotation: (any MKAnnotation)? {
        didSet {
            applyStyle()
        }
    }

    /// Re-applied on init, reuse and every annotation change so a reused view can never
    /// keep the previous contact's photo.
    private func applyStyle() {
        clusteringIdentifier = ContactAnnotationView.contactClusteringIdentifier
        collisionMode = .circle
        canShowCallout = true
        if rightCalloutAccessoryView == nil {
            rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        }

        let pin = Self.pinImage(photo: (annotation as? ContactAnnotation)?.photo)
        image = pin
        // Lift the image so the pointer's tip, not its centre, sits on the coordinate.
        centerOffset = CGPoint(x: 0, y: -pin.size.height / 2)
    }

    /// The circular photo in a white ring, with a pointer underneath. Without a photo it
    /// falls back to a person symbol so the pin is never blank.
    static func pinImage(photo: UIImage?) -> UIImage {
        let outerDiameter = photoDiameter + borderWidth * 2
        let size = CGSize(width: outerDiameter, height: outerDiameter + pointerHeight)

        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()

            let pointer = UIBezierPath()
            pointer.move(to: CGPoint(x: outerDiameter / 2 - pointerHalfWidth, y: outerDiameter - 4))
            pointer.addLine(to: CGPoint(x: outerDiameter / 2, y: size.height))
            pointer.addLine(to: CGPoint(x: outerDiameter / 2 + pointerHalfWidth, y: outerDiameter - 4))
            pointer.close()
            pointer.fill()

            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: outerDiameter, height: outerDiameter)).fill()

            let photoRect = CGRect(x: borderWidth, y: borderWidth, width: photoDiameter, height: photoDiameter)
            UIBezierPath(ovalIn: photoRect).addClip()

            guard let photo, photo.size.width > 0, photo.size.height > 0 else {
                UIColor.systemGray.setFill()
                UIRectFill(photoRect)
                let symbol = UIImage(systemName: "person.fill")?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                symbol?.draw(in: photoRect.insetBy(dx: 10, dy: 10))
                return
            }

            // Aspect-fill: scale the photo to cover the circle, cropping the overflow.
            let scale = max(photoDiameter / photo.size.width, photoDiameter / photo.size.height)
            let drawSize = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(
                x: photoRect.midX - drawSize.width / 2,
                y: photoRect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }
}
