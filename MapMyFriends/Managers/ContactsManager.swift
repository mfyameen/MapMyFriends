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
        let phoneNumber: String?
    }

    /// Outcome of a contact fetch. `failed` and `denied` must never be mistaken for
    /// "the user has no contacts", or a refresh would diff every pin off the map.
    enum FetchResult: Sendable {
        case success([RawContactAddress])
        case denied
        case failed
    }

    /// Walks the contact store, handing each contact to the block. Injected in tests.
    typealias ContactEnumerator = (CNContactFetchRequest, (CNContact) -> Void) throws -> Void

    nonisolated static var keysToFetch: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
    }

    private let store = CNContactStore()

    func requestAccessAndFetch(completion: @escaping @MainActor @Sendable (FetchResult) -> Void) {
        store.requestAccess(for: .contacts) { [weak self] granted, _ in
            guard granted, let self else {
                Task { @MainActor in completion(.denied) }
                return
            }
            self.fetchContacts(completion: completion)
        }
    }

    /// Enumerates every contact and flattens them into one entry per postal address.
    nonisolated static func collectAddresses(using enumerate: ContactEnumerator) -> FetchResult {
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        let formatter = CNPostalAddressFormatter()
        var results: [RawContactAddress] = []

        do {
            try enumerate(request) { contact in
                results.append(contentsOf: rawAddresses(from: contact, formatter: formatter))
            }
        } catch {
            // Whatever was collected before the error is incomplete. Reporting it as the full
            // list would make a refresh remove every contact that wasn't reached.
            #if DEBUG
            print("[ContactsManager] Failed to fetch contacts: \(error)")
            #endif
            return .failed
        }

        return .success(results)
    }

    /// One entry per non-empty postal address on the contact.
    nonisolated static func rawAddresses(
        from contact: CNContact,
        formatter: CNPostalAddressFormatter
    ) -> [RawContactAddress] {
        let fullName = displayName(for: contact)

        // Prefer mobile, then first available
        let phoneNumber: String? = {
            let phones = contact.phoneNumbers
            let mobile = phones.first { $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone }
            return (mobile ?? phones.first)?.value.stringValue
        }()

        var results: [RawContactAddress] = []
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
                thumbnailImageData: contact.thumbnailImageData,
                phoneNumber: phoneNumber
            ))
        }
        return results
    }

    /// The name a pin shows. Company-only and nickname-only contacts still have an
    /// address worth mapping, so they fall back rather than being dropped.
    nonisolated static func displayName(for contact: CNContact) -> String {
        let personName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        for candidate in [personName, contact.organizationName, contact.nickname] where !candidate.isEmpty {
            return candidate
        }
        return "No Name"
    }

    // MARK: - Private

    private nonisolated func fetchContacts(completion: @escaping @MainActor @Sendable (FetchResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let result = Self.collectAddresses { request, block in
                try store.enumerateContacts(with: request) { contact, _ in block(contact) }
            }
            Task { @MainActor in completion(result) }
        }
    }
}
