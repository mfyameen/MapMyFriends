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

    /// Cached entries older than this are treated as stale and re-geocoded.
    static let cacheTTL: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    private var cache: [String: CachedCoordinate] = [:]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.mapmyfriends.cachemanager")
    private let ttl: TimeInterval

    /// Production singleton init — uses the app's documents directory.
    private convenience init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("address_cache.json")
        self.init(fileURL: url)
    }

    /// Testable init — accepts a custom file URL and optional TTL for isolated testing.
    init(fileURL: URL, ttl: TimeInterval = CacheManager.cacheTTL) {
        self.fileURL = fileURL
        self.ttl = ttl
        loadFromDisk()
    }

    // MARK: - Public

    func coordinate(for address: String) -> CachedCoordinate? {
        queue.sync {
            guard let entry = cache[address] else { return nil }
            // Treat entries older than TTL as stale
            if Date().timeIntervalSince(entry.cachedAt) > ttl {
                return nil
            }
            return entry
        }
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
