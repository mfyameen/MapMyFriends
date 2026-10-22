//
//  UnmappedContact.swift
//  MapMyFriends
//

/// A contact address that isn't on the map, and why.
struct UnmappedContact: Equatable, Hashable, Sendable {

    enum Reason: Equatable, Hashable, Sendable {
        /// Apple Maps has no place for the address (or it couldn't be read as one).
        /// Fixing the address in Contacts is the way forward.
        case addressNotFound
        /// The lookup didn't get an answer (offline, server error, throttled). Retried
        /// automatically next time the app comes to the foreground.
        case couldNotConnect
    }

    let contactID: String
    let fullName: String
    let addressString: String
    let reason: Reason

    /// Same identity as a pin: one contact can have several addresses.
    var key: String { "\(contactID)|\(addressString)" }
}
