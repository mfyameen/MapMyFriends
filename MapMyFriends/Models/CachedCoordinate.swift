//
//  CachedCoordinate.swift
//  MapMyFriends
//

import Foundation

struct CachedCoordinate: Codable, Sendable {
    let lat: Double
    let lng: Double
    let cachedAt: Date
}
