//
//  GeocodingManager.swift
//  MapMyFriends
//

import MapKit

@MainActor
class GeocodingManager {

    /// Breakdown of a single `process()` run, for observability when toasts are hidden.
    struct Summary: Equatable {
        /// Contacts resolved straight from a valid cache entry.
        var resolvedFromCache = 0
        /// Contacts resolved by a live geocode this run.
        var geocoded = 0
        /// Addresses that could not be geocoded this run (includes `invalidAddressStrings`).
        var failed = 0
        /// Subset of `failed` where `MKGeocodingRequest` could not even be constructed.
        var invalidAddressStrings = 0
        /// Legacy `failed: true` cache entries written by older builds that we now retry
        /// instead of silently dropping.
        var retriedCachedFailures = 0

        var attempted: Int { resolvedFromCache + geocoded + failed }
    }

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Called when all geocoding is finished. Parameter is the number of addresses that failed to geocode.
    var onComplete: ((Int) -> Void)?
    /// Called immediately before `onComplete` with the full breakdown of the run.
    var onSummary: ((Summary) -> Void)?

    private let cache: CacheManaging
    private let geocoder: AddressGeocoding
    /// Pause between geocodes to respect Apple rate limits. Tests set this to 0 to run synchronously.
    private let requestDelay: TimeInterval
    private var isCancelled = false
    private var summary = Summary()

    /// Defaults are built inside the body rather than as default argument expressions,
    /// which are evaluated in a nonisolated context and cannot touch main-actor state.
    /// - Parameter geocoder: Defaults to `MapKitGeocoder`. Injected in tests to run offline.
    init(
        cache: CacheManaging? = nil,
        geocoder: AddressGeocoding? = nil,
        requestDelay: TimeInterval = 0.15
    ) {
        self.cache = cache ?? CacheManager.shared
        self.geocoder = geocoder ?? MapKitGeocoder()
        self.requestDelay = requestDelay
    }

    /// Process addresses for geocoding. If `userLocation` is provided, cached contacts are
    /// delivered nearest-first so nearby pins appear on the map before distant ones.
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil) {
        isCancelled = false
        summary = Summary()

        var resolvedHits: [MappedContact] = []
        var cacheMisses: [ContactsManager.RawContactAddress] = []

        for address in addresses {
            // Single lookup per address (no double lookup)
            let cached = cache.coordinate(for: address.addressString)

            if let cached, !cached.failed {
                resolvedHits.append(MappedContact(
                    contactID: address.contactID,
                    fullName: address.fullName,
                    addressLabel: address.addressLabel,
                    addressString: address.addressString,
                    coordinate: CLLocationCoordinate2D(latitude: cached.lat, longitude: cached.lng),
                    thumbnailImageData: address.thumbnailImageData,
                    phoneNumber: address.phoneNumber
                ))
                continue
            }

            if cached?.failed == true {
                // Legacy failure entry from an older build. Never skip it — a transient
                // failure must not hide a contact until the entry expires.
                summary.retriedCachedFailures += 1
            }

            cacheMisses.append(address)
        }

        summary.resolvedFromCache = resolvedHits.count

        // Sort cache hits by proximity to user so nearby pins appear first
        if let userLocation {
            let userCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            resolvedHits.sort { a, b in
                let distA = userCL.distance(from: CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude))
                let distB = userCL.distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
                return distA < distB
            }
        }

        for contact in resolvedHits {
            onContactResolved?(contact)
        }

        // Process cache misses sequentially
        guard !cacheMisses.isEmpty else {
            finish()
            return
        }

        geocodeSequentially(addresses: cacheMisses, index: 0, total: cacheMisses.count)
    }

    func cancel() {
        isCancelled = true
        geocoder.cancelInFlight()
        cache.saveToDisk()
    }

    // MARK: - Private

    private func finish() {
        logSummary()
        onSummary?(summary)
        onComplete?(summary.failed)
    }

    private func logSummary() {
        #if DEBUG
        // Always log, regardless of `hideGeocodingToasts`, so missing pins are diagnosable.
        print("""
        [GeocodingManager] FromCache: \(summary.resolvedFromCache), \
        Geocoded: \(summary.geocoded), \
        Failed: \(summary.failed) (invalid: \(summary.invalidAddressStrings)), \
        RetriedCachedFailures: \(summary.retriedCachedFailures)
        """)
        #endif
    }

    private func geocodeSequentially(addresses: [ContactsManager.RawContactAddress], index: Int, total: Int) {
        var index = index

        while true {
            guard !isCancelled, index < addresses.count else {
                cache.saveToDisk()
                finish()
                return
            }

            let address = addresses[index]
            let completed = index + 1

            // A geocoder that calls back before `geocode` returns advances this loop instead
            // of recursing, so a 1000-address run doesn't build a 1000-frame stack. The
            // production geocoder is asynchronous and takes the scheduled path below.
            var isCallbackOnStack = true
            var advanceInLoop = false

            geocoder.geocode(address.addressString) { [weak self] outcome in
                guard let self, !self.isCancelled else { return }

                self.record(outcome: outcome, for: address)
                self.onProgress?(completed, total)

                // Persist every 10 geocodes to protect progress if the app is killed
                if completed % 10 == 0 {
                    self.cache.saveToDisk()
                }

                guard self.requestDelay > 0 else {
                    if isCallbackOnStack {
                        advanceInLoop = true
                    } else {
                        self.geocodeSequentially(addresses: addresses, index: completed, total: total)
                    }
                    return
                }

                // Delay before next geocode to respect Apple rate limits
                DispatchQueue.main.asyncAfter(deadline: .now() + self.requestDelay) {
                    self.geocodeSequentially(addresses: addresses, index: completed, total: total)
                }
            }

            isCallbackOnStack = false

            // The callback scheduled the next step itself; this walk is done here.
            guard advanceInLoop else { return }
            index = completed
        }
    }

    private func record(outcome: GeocodeOutcome, for address: ContactsManager.RawContactAddress) {
        switch outcome {
        case .success(let coordinate):
            let cached = CachedCoordinate(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                cachedAt: Date()
            )
            cache.store(coordinate: cached, for: address.addressString)
            summary.geocoded += 1

            onContactResolved?(MappedContact(
                contactID: address.contactID,
                fullName: address.fullName,
                addressLabel: address.addressLabel,
                addressString: address.addressString,
                coordinate: coordinate,
                thumbnailImageData: address.thumbnailImageData,
                phoneNumber: address.phoneNumber
            ))

        case .invalidAddress:
            // Deliberately NOT cached as a failure: constructing the request is free
            // (no network call) and can fail for valid addresses due to formatting or
            // encoding quirks. Retry on the next launch.
            summary.failed += 1
            summary.invalidAddressStrings += 1
            #if DEBUG
            print("[GeocodingManager] Invalid address string: '\(address.addressString)'")
            #endif

        case .failed(let reason):
            // Deliberately NOT cached as a failure. A transient network error or rate limit
            // must not hide this contact until a cache entry expires — retry next launch.
            summary.failed += 1
            #if DEBUG
            print("[GeocodingManager] Failed to geocode '\(address.addressString)': \(reason ?? "no results")")
            #endif
        }
    }
}
