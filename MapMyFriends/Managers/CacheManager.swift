//
//  CacheManager.swift
//  MapMyFriends
//

import Foundation

// MARK: - Protocol

protocol CacheManaging {
    func coordinate(for address: String) -> CachedCoordinate?
    func store(coordinate: CachedCoordinate, for address: String)
    func saveToDisk()
}

// MARK: - Implementation

class CacheManager: CacheManaging {
    static let shared = CacheManager()

    private var cache: [String: CachedCoordinate] = [:]
    private let fileURL: URL

    /// Production singleton init — uses the app's documents directory.
    private convenience init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("address_cache.json")
        self.init(fileURL: url)
    }

    /// Testable init — accepts a custom file URL for isolated testing.
    init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }

    // MARK: - Public

    func coordinate(for address: String) -> CachedCoordinate? {
        cache[address]
    }

    func store(coordinate: CachedCoordinate, for address: String) {
        cache[address] = coordinate
    }

    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[CacheManager] Failed to save cache: \(error)")
        }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            cache = try JSONDecoder().decode([String: CachedCoordinate].self, from: data)
        } catch {
            print("[CacheManager] Failed to load cache: \(error)")
            cache = [:]
        }
    }
}
