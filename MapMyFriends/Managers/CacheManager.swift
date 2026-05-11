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
    nonisolated(unsafe) static let shared = CacheManager()

    private var cache: [String: CachedCoordinate] = [:]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.mapmyfriends.cachemanager")

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
        queue.sync { cache[address] }
    }

    func store(coordinate: CachedCoordinate, for address: String) {
        queue.sync { cache[address] = coordinate }
    }

    func saveToDisk() {
        let snapshot = queue.sync { cache }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            #if DEBUG
            print("[CacheManager] Failed to save cache: \(error)")
            #endif
        }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            cache = try JSONDecoder().decode([String: CachedCoordinate].self, from: data)
        } catch {
            #if DEBUG
            print("[CacheManager] Failed to load cache: \(error)")
            #endif
            cache = [:]
        }
    }
}
