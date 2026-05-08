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
}
