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
    /// Uses (contactID, addressString) as the identity key.
    static func diff(
        newAddresses: [ContactsManager.RawContactAddress],
        existing: [MappedContact]
    ) -> DiffResult {
        let newSet = Set(newAddresses.map { "\($0.contactID)|\($0.addressString)" })
        let existingSet = Set(existing.map { "\($0.contactID)|\($0.addressString)" })

        let toRemoveIndices = existing.enumerated().compactMap { index, contact in
            let key = "\(contact.contactID)|\(contact.addressString)"
            return newSet.contains(key) ? nil : index
        }

        let toAdd = newAddresses.filter { address in
            let key = "\(address.contactID)|\(address.addressString)"
            return !existingSet.contains(key)
        }

        return DiffResult(toRemoveIndices: toRemoveIndices, toAdd: toAdd)
    }
}
