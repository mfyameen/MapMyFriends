//
//  UnmappedContactsView.swift
//  MapMyFriends
//

import SwiftUI

/// The list behind the "N not on the map" button: who's missing and why. Tapping a contact
/// opens it so the address can be fixed.
struct UnmappedContactsView: View {

    let contacts: [UnmappedContact]
    let onSelect: (UnmappedContact) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(contacts, id: \.key) { contact in
                        Button {
                            onSelect(contact)
                        } label: {
                            row(for: contact)
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Addresses Apple Maps couldn't find need fixing in Contacts. Connection problems are retried automatically when you come back to the app.")
                }
            }
            .navigationTitle("Not on the Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func row(for contact: UnmappedContact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.fullName)
                .font(.headline)
            Text(contact.addressString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(reasonText(contact.reason), systemImage: reasonSymbol(contact.reason))
                .font(.footnote)
                .foregroundStyle(contact.reason == .addressNotFound ? .orange : .secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the contact")
    }

    private func reasonText(_ reason: UnmappedContact.Reason) -> String {
        switch reason {
        case .addressNotFound: "Address not found"
        case .couldNotConnect: "Couldn't reach Apple Maps"
        }
    }

    private func reasonSymbol(_ reason: UnmappedContact.Reason) -> String {
        switch reason {
        case .addressNotFound: "mappin.slash"
        case .couldNotConnect: "wifi.exclamationmark"
        }
    }
}
