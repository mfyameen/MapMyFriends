//
//  ContactDifferTests.swift
//  MapMyFriendsTests
//

import CoreLocation
import Testing
@testable import MapMyFriends

struct ContactDifferTests {

    // MARK: - Helpers

    private func makeAddress(id: String, address: String) -> ContactsManager.RawContactAddress {
        ContactsManager.RawContactAddress(
            contactID: id,
            fullName: "Name",
            addressLabel: "Home",
            addressString: address,
            thumbnailImageData: nil
        )
    }

    private func makeContact(id: String, address: String) -> MappedContact {
        MappedContact(
            contactID: id,
            fullName: "Name",
            addressLabel: "Home",
            addressString: address,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            thumbnailImageData: nil
        )
    }

    // MARK: - No Changes

    @Test func noChangesProducesEmptyDiff() {
        let addresses = [makeAddress(id: "1", address: "123 Main St")]
        let existing = [makeContact(id: "1", address: "123 Main St")]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.isEmpty)
    }

    @Test func bothEmpty() {
        let result = ContactDiffer.diff(newAddresses: [], existing: [])

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.isEmpty)
    }

    // MARK: - Additions

    @Test func newContactAdded() {
        let addresses = [
            makeAddress(id: "1", address: "123 Main St"),
            makeAddress(id: "2", address: "456 Oak Ave"),
        ]
        let existing = [makeContact(id: "1", address: "123 Main St")]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.count == 1)
        #expect(result.toAdd.first?.contactID == "2")
    }

    @Test func newAddressAddedToExistingContact() {
        let addresses = [
            makeAddress(id: "1", address: "123 Main St"),
            makeAddress(id: "1", address: "789 Work Blvd"),
        ]
        let existing = [makeContact(id: "1", address: "123 Main St")]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices.isEmpty)
        #expect(result.toAdd.count == 1)
        #expect(result.toAdd.first?.addressString == "789 Work Blvd")
    }

    // MARK: - Removals

    @Test func contactDeleted() {
        let addresses: [ContactsManager.RawContactAddress] = []
        let existing = [makeContact(id: "1", address: "123 Main St")]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices == [0])
        #expect(result.toAdd.isEmpty)
    }

    @Test func addressRemovedFromContact() {
        let addresses = [makeAddress(id: "1", address: "123 Main St")]
        let existing = [
            makeContact(id: "1", address: "123 Main St"),
            makeContact(id: "1", address: "789 Work Blvd"),
        ]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices == [1])
        #expect(result.toAdd.isEmpty)
    }

    // MARK: - Address Changed

    @Test func addressChanged() {
        let addresses = [makeAddress(id: "1", address: "999 New St")]
        let existing = [makeContact(id: "1", address: "123 Old St")]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices == [0], "Old address should be removed")
        #expect(result.toAdd.count == 1, "New address should be added")
        #expect(result.toAdd.first?.addressString == "999 New St")
    }

    // MARK: - Mixed Changes

    @Test func mixedAddRemoveKeep() {
        // Existing: contact 1 at addr A, contact 2 at addr B
        // New:      contact 1 at addr A (kept), contact 3 at addr C (added)
        // Expected: remove contact 2, add contact 3
        let addresses = [
            makeAddress(id: "1", address: "A"),
            makeAddress(id: "3", address: "C"),
        ]
        let existing = [
            makeContact(id: "1", address: "A"),
            makeContact(id: "2", address: "B"),
        ]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices == [1])
        #expect(result.toAdd.count == 1)
        #expect(result.toAdd.first?.contactID == "3")
    }

    @Test func multipleRemovalsPreserveCorrectIndices() {
        let addresses: [ContactsManager.RawContactAddress] = []
        let existing = [
            makeContact(id: "1", address: "A"),
            makeContact(id: "2", address: "B"),
            makeContact(id: "3", address: "C"),
        ]

        let result = ContactDiffer.diff(newAddresses: addresses, existing: existing)

        #expect(result.toRemoveIndices.sorted() == [0, 1, 2])
    }
}
