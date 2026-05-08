//
//  MapViewControllerWrapper.swift
//  MapMyFriends
//

import SwiftUI

struct MapViewControllerWrapper: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UINavigationController {
        let mapVC = MapViewController()
        return UINavigationController(rootViewController: mapVC)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No dynamic updates needed
    }
}
