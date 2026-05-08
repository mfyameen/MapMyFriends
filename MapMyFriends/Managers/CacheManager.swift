//
//  CacheManager.swift
//  MapMyFriends
//

import Foundation

class CacheManager {
    static let shared = CacheManager()

    private var cache: [String: CachedCoordinate] = [:]

    private var cacheFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("address_cache.json")
    }

    private init() {
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
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            print("[CacheManager] Failed to save cache: \(error)")
        }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            cache = try JSONDecoder().decode([String: CachedCoordinate].self, from: data)
        } catch {
            print("[CacheManager] Failed to load cache: \(error)")
            cache = [:]
        }
    }
}
