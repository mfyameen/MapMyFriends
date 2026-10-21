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
    /// A pin is kept only if everything it displays is unchanged; an edited name, label or
    /// phone number replaces the pin (cheap: the address is still cached).
    static func diff(
        newAddresses: [ContactsManager.RawContactAddress],
        existing: [MappedContact]
    ) -> DiffResult {
        let newSet = Set(newAddresses.map {
            key($0.contactID, $0.addressString, $0.fullName, $0.addressLabel, $0.phoneNumber)
        })
        let existingKeys = existing.map {
            key($0.contactID, $0.addressString, $0.fullName, $0.addressLabel, $0.phoneNumber)
        }
        let existingSet = Set(existingKeys)

        let toRemoveIndices = existingKeys.enumerated().compactMap { index, key in
            newSet.contains(key) ? nil : index
        }

        let toAdd = newAddresses.filter { address in
            !existingSet.contains(key(address.contactID, address.addressString, address.fullName, address.addressLabel, address.phoneNumber))
        }

        return DiffResult(toRemoveIndices: toRemoveIndices, toAdd: toAdd)
    }

    private static func key(_ contactID: String, _ address: String, _ name: String, _ label: String, _ phone: String?) -> [String] {
        [contactID, address, name, label, phone ?? ""]
    }
}
