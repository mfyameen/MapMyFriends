//
//  FeatureFlags.swift
//  MapMyFriends
//

import Foundation

/// Centralized feature flags for gating new or experimental behavior.
enum FeatureFlags {

    // MARK: - Pin Tap Action

    /// When `true`, tapping a pin's callout opens the contact directly in the Contacts app.
    /// When `false`, shows an action sheet with Call / Message options.
    ///
    /// **Decision needed:** Choose one behavior or expose as a user-facing setting.
    /// See: https://github.com/mfyameen/MapMyFriends/issues — "Pin tap action: Contacts app vs Call/Message sheet"
    static let openContactOnPinTap = true

    // MARK: - Geocoding UI

    /// When `true`, suppresses the "Mapping X of Y contacts…" progress banner
    /// and the "X addresses could not be mapped" error toast.
    static let hideGeocodingToasts = true
}
