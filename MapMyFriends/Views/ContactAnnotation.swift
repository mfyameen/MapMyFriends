//
//  ContactAnnotation.swift
//  MapMyFriends
//

import MapKit

class ContactAnnotation: NSObject, MKAnnotation {
    let mappedContact: MappedContact

    var coordinate: CLLocationCoordinate2D { mappedContact.coordinate }
    var title: String? { mappedContact.fullName }
    /// Callouts show a single line, so the address's line breaks become commas — otherwise
    /// everything after the street (city, state) was cut off.
    var subtitle: String? { "\(mappedContact.addressLabel) · \(oneLineAddress)" }

    var oneLineAddress: String {
        mappedContact.addressString
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init(mappedContact: MappedContact) {
        self.mappedContact = mappedContact
    }

    /// What VoiceOver reads for this pin: name, label and the address with its line breaks
    /// turned into pauses.
    var accessibilityDescription: String {
        "\(mappedContact.fullName), \(mappedContact.addressLabel), \(oneLineAddress)"
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
