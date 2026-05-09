//
//  ContactsManager.swift
//  MapMyFriends
//

import Contacts

class ContactsManager {

    struct RawContactAddress: Sendable {
        let contactID: String
        let fullName: String
        let addressLabel: String
        let addressString: String
        let thumbnailImageData: Data?
    }

    private let store = CNContactStore()

    func requestAccessAndFetch(completion: @escaping @Sendable ([RawContactAddress]) -> Void) {
        store.requestAccess(for: .contacts) { [weak self] granted, _ in
            guard granted, let self else {
                Task { @MainActor in completion([]) }
                return
            }
            self.fetchContacts(completion: completion)
        }
    }

    // MARK: - Private

    private nonisolated func fetchContacts(completion: @escaping @Sendable ([RawContactAddress]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
            ]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            let formatter = CNPostalAddressFormatter()
            var results: [RawContactAddress] = []

            do {
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let fullName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    guard !fullName.isEmpty else { return }

                    for labeledAddress in contact.postalAddresses {
                        let label: String
                        if let rawLabel = labeledAddress.label {
                            label = CNLabeledValue<NSString>.localizedString(forLabel: rawLabel)
                        } else {
                            label = "Other"
                        }

                        let addressString = formatter.string(from: labeledAddress.value)
                        guard !addressString.isEmpty else { continue }

                        results.append(RawContactAddress(
                            contactID: contact.identifier,
                            fullName: fullName,
                            addressLabel: label,
                            addressString: addressString,
                            thumbnailImageData: contact.thumbnailImageData
                        ))
                    }
                }
            } catch {
                #if DEBUG
                print("[ContactsManager] Failed to fetch contacts: \(error)")
                #endif
            }

            let finalResults = results
            Task { @MainActor in completion(finalResults) }
        }
    }
}
