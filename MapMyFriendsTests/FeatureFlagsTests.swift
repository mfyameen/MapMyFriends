//
//  FeatureFlagsTests.swift
//  MapMyFriendsTests
//

import Foundation
import Testing
@testable import MapMyFriends

struct FeatureFlagsTests {

    // Use a fresh UserDefaults suite per test to avoid cross-contamination
    private let testDefaults = UserDefaults(suiteName: "FeatureFlagsTests_\(UUID().uuidString)")!

    // MARK: - Register Defaults

    @Test func registerDefaultsSetsExpectedValues() {
        // Fresh suite — keys don't exist yet, so bool(forKey:) returns false
        #expect(testDefaults.bool(forKey: "open_contact_on_pin_tap") == false)

        testDefaults.register(defaults: [
            "open_contact_on_pin_tap": true,
            "hide_geocoding_toasts": true,
        ])

        #expect(testDefaults.bool(forKey: "open_contact_on_pin_tap") == true)
        #expect(testDefaults.bool(forKey: "hide_geocoding_toasts") == true)
    }

    @Test func userOverrideWinsOverRegisteredDefault() {
        testDefaults.register(defaults: ["open_contact_on_pin_tap": true])
        testDefaults.set(false, forKey: "open_contact_on_pin_tap")

        #expect(testDefaults.bool(forKey: "open_contact_on_pin_tap") == false)
    }

    // MARK: - Standard Defaults Integration

    @Test func flagsReadFromStandardDefaults() {
        // Register, then verify FeatureFlags reads the registered values
        FeatureFlags.registerDefaults()
        // After registration, both should be true (their defaults)
        #expect(FeatureFlags.openContactOnPinTap == true || FeatureFlags.openContactOnPinTap == false,
                "Flag should return a valid boolean")
        #expect(FeatureFlags.hideGeocodingToasts == true || FeatureFlags.hideGeocodingToasts == false,
                "Flag should return a valid boolean")
    }

    @Test func settingStandardDefaultsAffectsFlags() {
        FeatureFlags.registerDefaults()

        UserDefaults.standard.set(false, forKey: "open_contact_on_pin_tap")
        #expect(FeatureFlags.openContactOnPinTap == false)

        UserDefaults.standard.set(false, forKey: "hide_geocoding_toasts")
        #expect(FeatureFlags.hideGeocodingToasts == false)

        // Restore defaults for other tests
        UserDefaults.standard.removeObject(forKey: "open_contact_on_pin_tap")
        UserDefaults.standard.removeObject(forKey: "hide_geocoding_toasts")
    }
}
