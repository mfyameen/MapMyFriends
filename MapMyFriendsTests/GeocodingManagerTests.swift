//
//  GeocodingManagerTests.swift
//  MapMyFriendsTests
//

import CoreLocation
import Foundation
import Testing
@testable import MapMyFriends

struct GeocodingManagerTests {

    private func makeAddress(id: String = "1", name: String = "Test", address: String = "123 Main St") -> ContactsManager.RawContactAddress {
        ContactsManager.RawContactAddress(
            contactID: id,
            fullName: name,
            addressLabel: "Home",
            addressString: address,
            thumbnailImageData: nil
        )
    }

    @Test func allCacheHitsDeliverContacts() {
        let mockCache = MockCacheManager()
        mockCache.storage["123 Main St"] = CachedCoordinate(lat: 37.0, lng: -122.0, cachedAt: Date())
        mockCache.storage["456 Oak Ave"] = CachedCoordinate(lat: 38.0, lng: -121.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolvedCount = 0
        var completeCalled = false

        manager.onContactResolved = { _ in resolvedCount += 1 }
        manager.onComplete = { completeCalled = true }

        manager.process(addresses: [
            makeAddress(id: "1", address: "123 Main St"),
            makeAddress(id: "2", address: "456 Oak Ave"),
        ])

        #expect(resolvedCount == 2)
        #expect(completeCalled)
    }

    @Test func emptyInputCallsComplete() {
        let manager = GeocodingManager(cache: MockCacheManager())
        var completeCalled = false
        manager.onComplete = { completeCalled = true }

        manager.process(addresses: [])

        #expect(completeCalled)
    }

    @Test func cacheHitCoordinatesAreCorrect() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 40.0, lng: -74.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        manager.process(addresses: [makeAddress(address: "addr")])

        #expect(resolved?.coordinate.latitude == 40.0)
        #expect(resolved?.coordinate.longitude == -74.0)
    }

    @Test func cancelTriggersSave() {
        let mockCache = MockCacheManager()
        let manager = GeocodingManager(cache: mockCache)

        manager.cancel()

        #expect(mockCache.saveToDiskCallCount == 1)
    }

    @Test func allCacheHitsDoNotTriggerSave() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 1.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        manager.onComplete = {}

        manager.process(addresses: [makeAddress(address: "addr")])

        // With all cache hits and no misses, onComplete fires but saveToDisk is only called
        // in the sequential geocode path. All-hits path does not save (nothing new to persist).
        #expect(mockCache.saveToDiskCallCount == 0)
    }

    @Test func resolvedContactPreservesMetadata() {
        let mockCache = MockCacheManager()
        mockCache.storage["addr"] = CachedCoordinate(lat: 1.0, lng: 2.0, cachedAt: Date())

        let manager = GeocodingManager(cache: mockCache)
        var resolved: MappedContact?
        manager.onContactResolved = { resolved = $0 }

        let address = ContactsManager.RawContactAddress(
            contactID: "xyz",
            fullName: "John Smith",
            addressLabel: "Work",
            addressString: "addr",
            thumbnailImageData: nil
        )
        manager.process(addresses: [address])

        #expect(resolved?.contactID == "xyz")
        #expect(resolved?.fullName == "John Smith")
        #expect(resolved?.addressLabel == "Work")
        #expect(resolved?.addressString == "addr")
    }
}
