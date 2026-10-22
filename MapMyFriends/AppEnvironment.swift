//
//  AppEnvironment.swift
//  MapMyFriends
//

import Foundation

/// Facts about how the app was launched.
enum AppEnvironment {

    /// `true` when the app is the host for the unit tests. Xcode sets this variable for the
    /// test runner on every run, from the IDE or `xcodebuild test`.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
