//
//  MappedContact.swift
//  MapMyFriends
//

import CoreLocation

struct MappedContact: Sendable {
    let contactID: String
    let fullName: String
    let addressLabel: String
    let addressString: String
    let coordinate: CLLocationCoordinate2D
}
