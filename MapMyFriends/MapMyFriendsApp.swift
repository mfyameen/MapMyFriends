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
    var body: some Scene {
        WindowGroup {
            MapViewControllerWrapper()
                .ignoresSafeArea()
        }
    }
}
