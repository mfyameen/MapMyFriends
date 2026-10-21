//
//  ContactDiffer.swift
//  MapMyFriends
//

import Foundation

/// Pure-function diff logic for comparing new contact addresses against existing mapped contacts.
enum ContactDiffer {

    struct DiffResult {
        /// Indices into the existing array that should be removed from the map.
        let toRemoveIndices: [Int]
        /// Addresses from the new array that need to be geocoded and added.
        let toAdd: [ContactsManager.RawContactAddress]
    }

    /// Computes the diff between new contact addresses and existing mapped contacts.
    /// A pin is kept only if everything it displays is unchanged; an edited name, label,
    /// phone number or photo replaces the pin (cheap: the address is still cached).
    static func diff(
        newAddresses: [ContactsManager.RawContactAddress],
        existing: [MappedContact]
    ) -> DiffResult {
        let newSet = Set(newAddresses.map {
            Identity($0.contactID, $0.addressString, $0.fullName, $0.addressLabel, $0.phoneNumber, $0.thumbnailImageData)
        })
        let existingKeys = existing.map {
            Identity($0.contactID, $0.addressString, $0.fullName, $0.addressLabel, $0.phoneNumber, $0.thumbnailImageData)
        }
        let existingSet = Set(existingKeys)

        let toRemoveIndices = existingKeys.enumerated().compactMap { index, key in
            newSet.contains(key) ? nil : index
        }

        let toAdd = newAddresses.filter { address in
            !existingSet.contains(Identity(
                address.contactID, address.addressString, address.fullName,
                address.addressLabel, address.phoneNumber, address.thumbnailImageData
            ))
        }

        return DiffResult(toRemoveIndices: toRemoveIndices, toAdd: toAdd)
    }

    /// Everything a pin displays. Equality compares the photo bytes in full.
    private struct Identity: Hashable {
        let contactID: String
        let address: String
        let name: String
        let label: String
        let phone: String?
        let photo: Data?

        init(_ contactID: String, _ address: String, _ name: String, _ label: String, _ phone: String?, _ photo: Data?) {
            self.contactID = contactID
            self.address = address
            self.name = name
            self.label = label
            self.phone = phone
            self.photo = photo
        }
    }
}
