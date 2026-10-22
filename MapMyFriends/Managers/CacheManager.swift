//
//  CacheManager.swift
//  MapMyFriends
//

import Foundation

// MARK: - Protocol

protocol CacheManaging {
    func coordinate(for address: String) -> CachedCoordinate?
    /// A successful entry that has outlived its TTL, or `nil`. Still a good guess for where
    /// the address is while a fresh geocode is pending or failing.
    func expiredCoordinate(for address: String) -> CachedCoordinate?
    func store(coordinate: CachedCoordinate, for address: String)
    /// Drops every entry whose address isn't in `addresses`, so a deleted contact's
    /// address doesn't stay on disk.
    func retainOnly(_ addresses: Set<String>)
    func saveToDisk()
}

// MARK: - Implementation

class CacheManager: CacheManaging {
    static let shared = CacheManager()

    /// Successful entries older than this are treated as stale and re-geocoded.
    static let cacheTTL: TimeInterval = 90 * 24 * 60 * 60 // 90 days

    /// Failed entries use a shorter TTL so transient failures are retried sooner.
    static let failedTTL: TimeInterval = 24 * 60 * 60 // 24 hours

    private var cache: [String: CachedCoordinate] = [:]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.mapmyfriends.cachemanager")
    private let ttl: TimeInterval
    private let failedTtl: TimeInterval
    /// The file exists but couldn't be read (e.g. still locked by Data Protection). Until a
    /// read succeeds, lookups retry it and saves must not replace it with a partial cache.
    private var needsReload = false

    private static let fileName = "address_cache.json"

    /// Where the production cache lives: Application Support, which isn't shown to the user.
    /// Saves also exclude it from backup — the app can rebuild it, and it holds every
    /// contact's address, so it shouldn't outlive deleting the app.
    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// Where builds before 1.0 kept the cache. Documents is backed up to iCloud.
    static func legacyFileURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// Moves a cache file left by an older build to `newURL`. If both exist the newer
    /// cache wins; either way the old, backed-up copy is removed.
    static func migrateLegacyFile(from legacyURL: URL, to newURL: URL, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        do {
            if fileManager.fileExists(atPath: newURL.path) {
                try fileManager.removeItem(at: legacyURL)
                return
            }
            try fileManager.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyURL, to: newURL)
            excludeFromBackup(newURL)
        } catch {
            #if DEBUG
            print("[CacheManager] Failed to migrate legacy cache: \(error)")
            #endif
        }
    }

    /// Production singleton init — uses Application Support, after moving any old cache out
    /// of Documents.
    private convenience init() {
        let url = Self.defaultFileURL()
        Self.migrateLegacyFile(from: Self.legacyFileURL(), to: url)
        self.init(fileURL: url)
    }

    /// Testable init — accepts a custom file URL and optional TTLs for isolated testing.
    init(fileURL: URL, ttl: TimeInterval = CacheManager.cacheTTL, failedTtl: TimeInterval = CacheManager.failedTTL) {
        self.fileURL = fileURL
        self.ttl = ttl
        self.failedTtl = failedTtl
        loadFromDisk()
    }

    // MARK: - Public

    func coordinate(for address: String) -> CachedCoordinate? {
        queue.sync {
            reloadIfNeeded()
            guard let entry = cache[address] else { return nil }
            let age = Date().timeIntervalSince(entry.cachedAt)
            let limit = entry.failed ? failedTtl : ttl
            if age > limit {
                return nil
            }
            return entry
        }
    }

    func expiredCoordinate(for address: String) -> CachedCoordinate? {
        queue.sync {
            reloadIfNeeded()
            guard let entry = cache[address], !entry.failed else { return nil }
            return Date().timeIntervalSince(entry.cachedAt) > ttl ? entry : nil
        }
    }

    func store(coordinate: CachedCoordinate, for address: String) {
        // NaN can't be encoded as JSON: one such entry would make every later save fail.
        guard coordinate.isEncodable else { return }
        queue.sync { cache[address] = coordinate }
    }

    func retainOnly(_ addresses: Set<String>) {
        queue.sync {
            reloadIfNeeded()
            cache = cache.filter { addresses.contains($0.key) }
        }
    }

    func saveToDisk() {
        let snapshot: [String: CachedCoordinate]? = queue.sync {
            reloadIfNeeded()
            return needsReload ? nil : cache
        }
        guard let snapshot else {
            // Writing now would replace every entry we couldn't read with just this session's.
            #if DEBUG
            print("[CacheManager] Cache file still unreadable; skipping save")
            #endif
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            // An atomic write replaces the file, dropping its resource values: re-apply every time.
            Self.excludeFromBackup(fileURL)
        } catch {
            #if DEBUG
            print("[CacheManager] Failed to save cache: \(error)")
            #endif
        }
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            #if DEBUG
            print("[CacheManager] Cache file unreadable, will retry: \(error)")
            #endif
            needsReload = true
            return
        }
        needsReload = false
        do {
            let decoded = try JSONDecoder().decode([String: CachedCoordinate].self, from: data)
            cache = decoded
        } catch {
            // Readable but corrupt: nothing to salvage, start fresh.
            #if DEBUG
            print("[CacheManager] Failed to load cache: \(error)")
            #endif
            cache = [:]
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Retries a read that failed at launch, keeping anything stored since. Call on `queue`.
    private func reloadIfNeeded() {
        guard needsReload else { return }
        let sessionEntries = cache
        loadFromDisk()
        guard !needsReload else { return }
        cache.merge(sessionEntries) { _, newer in newer }
    }
}

private extension CachedCoordinate {
    var isEncodable: Bool { lat.isFinite && lng.isFinite }
}
