//
//  ContactChangeCoalescer.swift
//  MapMyFriends
//

import Foundation

/// Decides what a `CNContactStoreDidChange` notification should do.
///
/// Granting contacts permission fires `CNContactStoreDidChange` while the initial geocoding
/// pass is still running. Refreshing on it cancels that pass and drops every contact that
/// hadn't been geocoded yet, so changes arriving during the initial load are deferred rather
/// than acted on — and deferred changes collapse into a single refresh.
///
/// Extracted from `MapViewController` so this gate is unit-testable without UIKit.
final class ContactChangeCoalescer {

    enum Decision: Equatable {
        /// The initial load is still running; the change has been recorded for later.
        case deferUntilInitialLoadCompletes
        /// Safe to refresh (subject to the caller's debounce window).
        case scheduleRefresh
    }

    private(set) var isInitialLoadComplete = false
    private(set) var hasPendingChange = false

    /// Records an incoming contact store change and returns what the caller should do.
    func noteChange() -> Decision {
        guard isInitialLoadComplete else {
            hasPendingChange = true
            return .deferUntilInitialLoadCompletes
        }
        return .scheduleRefresh
    }

    /// Marks the initial geocoding pass as finished.
    /// - Returns: `true` if changes arrived during the initial load and a refresh is now due.
    func noteInitialLoadComplete() -> Bool {
        let wasInitialLoad = !isInitialLoadComplete
        isInitialLoadComplete = true

        guard wasInitialLoad, hasPendingChange else { return false }
        hasPendingChange = false
        return true
    }
}
