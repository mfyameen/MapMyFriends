//
//  MapMyFriendsApp.swift
//  MapMyFriends
//
//  Created by @mfyameen on 5/8/26.
//  open source and available at https://github.com/mfyameen/MapMyFriends
//

import SwiftUI

@main
struct MapMyFriendsApp: App {

    init() {
        FeatureFlags.registerDefaults()
    }

    /// The unit tests run inside the app. Building the real screen there would ask for
    /// contacts and geocode real addresses while the suite runs, so tests get a blank one.
    static let shouldShowMap = !AppEnvironment.isRunningTests

    var body: some Scene {
        WindowGroup {
            if Self.shouldShowMap {
                MapViewControllerWrapper()
                    .ignoresSafeArea()
            } else {
                Color.clear
            }
        }
    }
}
