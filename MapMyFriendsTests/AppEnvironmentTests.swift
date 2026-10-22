//
//  AppEnvironmentTests.swift
//  MapMyFriendsTests
//

import Testing
@testable import MapMyFriends

/// The tests run inside the app. Unless it knows that, it asks for contacts and geocodes
/// real addresses against Apple's servers while the suite runs.
struct AppEnvironmentTests {

    @Test func knowsItIsRunningUnderTests() {
        #expect(AppEnvironment.isRunningTests)
    }

    @Test func appSkipsLoadingTheMapUnderTests() {
        #expect(!MapMyFriendsApp.shouldShowMap)
    }
}
