//
//  ContactAccessPickerHost.swift
//  MapMyFriends
//

import ContactsUI
import SwiftUI

/// Presents Apple's in-app picker for sharing more contacts under limited access, so the
/// user doesn't have to find the app in Settings. Changing which contacts are shared doesn't
/// post `CNContactStoreDidChange`, so the caller reloads contacts in `onFinish`.
struct ContactAccessPickerHost: View {

    let onFinish: () -> Void
    @State private var isPresented = false

    var body: some View {
        Color.clear
            .contactAccessPicker(isPresented: $isPresented) { _ in
                // Called back on an XPC thread, not the main one; dismissing from there crashes.
                DispatchQueue.main.async { onFinish() }
            }
            .onAppear { isPresented = true }
            .onChange(of: isPresented) { _, presented in
                if !presented { onFinish() }
            }
    }
}
