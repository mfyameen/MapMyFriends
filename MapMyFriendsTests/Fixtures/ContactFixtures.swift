//
//  ContactFixtures.swift
//  MapMyFriendsTests
//
//  Loads `contacts-1000.json` — a deterministic fixture of 1000 contact addresses
//  spanning all 50 US states, Washington DC, and 65 cities across 6 continents.
//
//  The file is read straight off disk via `#filePath` (the same approach as
//  `NoDataExfiltrationTests`) so it does not depend on test-bundle resource copying.
//

import CoreLocation
import Foundation
@testable import MapMyFriends

enum ContactFixtures {

    struct Contact: Decodable, Sendable, Equatable {
        let contactID: String
        let fullName: String
        let addressLabel: String
        let addressString: String
        let latitude: Double
        let longitude: Double
        let phoneNumber: String?
        let country: String
        let region: String

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var rawAddress: ContactsManager.RawContactAddress {
            ContactsManager.RawContactAddress(
                contactID: contactID,
                fullName: fullName,
                addressLabel: addressLabel,
                addressString: addressString,
                thumbnailImageData: nil,
                phoneNumber: phoneNumber
            )
        }
    }

    private struct Payload: Decodable {
        let schemaVersion: Int
        let count: Int
        let contacts: [Contact]
    }

    enum FixtureError: Error, CustomStringConvertible {
        case countMismatch(declared: Int, actual: Int)

        var description: String {
            switch self {
            case .countMismatch(let declared, let actual):
                return "Fixture declares \(declared) contacts but contains \(actual)"
            }
        }
    }

    static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Fixtures/
        .appendingPathComponent("contacts-1000.json")

    /// All 1000 fixture contacts, in file order.
    static let all: [Contact] = {
        do {
            return try load()
        } catch {
            fatalError("Failed to load contact fixture at \(fixtureURL.path): \(error)")
        }
    }()

    static func load() throws -> [Contact] {
        let data = try Data(contentsOf: fixtureURL)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.count == payload.contacts.count else {
            throw FixtureError.countMismatch(declared: payload.count, actual: payload.contacts.count)
        }
        return payload.contacts
    }

    // MARK: - Convenience

    /// The first `count` fixture contacts.
    static func first(_ count: Int) -> [Contact] {
        Array(all.prefix(count))
    }

    static func rawAddresses(_ contacts: [Contact]) -> [ContactsManager.RawContactAddress] {
        contacts.map(\.rawAddress)
    }

    /// A geocoder that resolves every supplied contact to its fixture coordinate.
    /// Anything not supplied falls back to a failure, so unexpected lookups are visible.
    static func geocoder(resolving contacts: [Contact]) -> MockGeocoder {
        let geocoder = MockGeocoder()
        for contact in contacts {
            geocoder.succeed(contact.addressString, lat: contact.latitude, lng: contact.longitude)
        }
        return geocoder
    }

    /// A cache pre-seeded with successful entries for the supplied contacts.
    static func warmCache(with contacts: [Contact]) -> MockCacheManager {
        let cache = MockCacheManager()
        for contact in contacts {
            cache.storeSuccess(contact.addressString, lat: contact.latitude, lng: contact.longitude)
        }
        return cache
    }
}
