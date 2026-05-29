//
//  FeatureFlags.swift
//  MapMyFriends
//

import Foundation

/// Centralized feature flags backed by UserDefaults.
/// Users can toggle these in the iOS Settings app (Settings > Map My Friends).
/// Values persist across launches.
enum FeatureFlags {

    // MARK: - Keys (must match Settings.bundle Root.plist)

    private enum Keys {
        static let openContactOnPinTap = "open_contact_on_pin_tap"
        static let hideGeocodingToasts = "hide_geocoding_toasts"
    }

    // MARK: - Defaults Registration

    /// Call once at app launch to ensure defaults exist before Settings is opened.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.openContactOnPinTap: true,
            Keys.hideGeocodingToasts: true,
        ])
    }

    // MARK: - Flags

    /// When `true`, tapping a pin's callout opens the contact directly in the Contacts app.
    /// When `false`, shows an action sheet with Call / Message options.
    static var openContactOnPinTap: Bool {
        UserDefaults.standard.bool(forKey: Keys.openContactOnPinTap)
    }

    /// When `true`, suppresses the "Mapping X of Y contacts…" progress banner
    /// and the "X addresses could not be mapped" error toast.
    static var hideGeocodingToasts: Bool {
        UserDefaults.standard.bool(forKey: Keys.hideGeocodingToasts)
    }
}
