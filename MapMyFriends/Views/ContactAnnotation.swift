//
//  ContactAnnotation.swift
//  MapMyFriends
//

import MapKit

class ContactAnnotation: NSObject, MKAnnotation {
    let mappedContact: MappedContact

    var coordinate: CLLocationCoordinate2D { mappedContact.coordinate }
    var title: String? { mappedContact.fullName }
    var subtitle: String? { "\(mappedContact.addressLabel) · \(mappedContact.addressString)" }

    init(mappedContact: MappedContact) {
        self.mappedContact = mappedContact
    }

    /// The contact's photo, if it has one that decodes. Decoded once, on first display.
    private(set) lazy var photo: UIImage? = mappedContact.thumbnailImageData.flatMap(UIImage.init(data:))

    /// The rendered photo pin, drawn once. MapKit reuses views constantly while panning, and
    /// each reuse would otherwise decode the photo and render it again.
    private(set) lazy var photoPinImage: UIImage = ContactPhotoAnnotationView.pinImage(photo: photo)

    /// Which annotation view draws this contact: the photo pin when there's a photo,
    /// otherwise the blue marker.
    var pinReuseIdentifier: String {
        photo != nil ? ContactPhotoAnnotationView.reuseIdentifier : MKMapViewDefaultAnnotationViewReuseIdentifier
    }
}
