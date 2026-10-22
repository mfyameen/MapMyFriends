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
        /// Contacts shown at their expired cached coordinate while a fresh geocode is queued.
        var resolvedFromExpiredCache = 0
        /// Contacts resolved by a live geocode this run.
        var geocoded = 0
        /// Addresses that could not be geocoded this run (includes `invalidAddressStrings`).
        var failed = 0
        /// Subset of `failed` where `MKGeocodingRequest` could not even be constructed.
        var invalidAddressStrings = 0
        /// Legacy `failed: true` cache entries written by older builds that we now retry
        /// instead of silently dropping.
        var retriedCachedFailures = 0
        /// Expired entries whose coordinate was successfully re-geocoded and re-cached.
        var refreshedExpired = 0

        var attempted: Int { resolvedFromCache + resolvedFromExpiredCache + geocoded + failed }
    }

    /// How many times one address is retried after Apple throttles it before it is reported
    /// as failed for this run. With the default backoff this waits out a full minute.
    static let maxRateLimitRetries = 4

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Called when all geocoding is finished. Parameter is the number of addresses that failed to geocode.
    var onComplete: ((Int) -> Void)?
    /// Called immediately before `onComplete` with the full breakdown of the run.
    var onSummary: ((Summary) -> Void)?

    /// One address to geocode. A refresh already has a pin (from an expired cache entry),
    /// so its result only updates the cache.
    private struct Job {
        let address: ContactsManager.RawContactAddress
        let isRefresh: Bool
    }

    private let cache: CacheManaging
    private let geocoder: AddressGeocoding
    /// Pause between geocodes to respect Apple rate limits. Tests set this to 0 to run synchronously.
    private let requestDelay: TimeInterval
    /// Base wait after Apple throttles a request; doubles on each consecutive throttle.
    private let rateLimitBackoff: TimeInterval
    /// Identifies the current run. `cancel()` and `process()` bump it, so responses and
    /// scheduled steps belonging to an earlier run are recognized and dropped.
    private var runID = 0
    private var summary = Summary()

    /// Defaults are built inside the body rather than as default argument expressions,
    /// which are evaluated in a nonisolated context and cannot touch main-actor state.
    /// - Parameter geocoder: Defaults to `MapKitGeocoder`. Injected in tests to run offline.
    init(
        cache: CacheManaging? = nil,
        geocoder: AddressGeocoding? = nil,
        requestDelay: TimeInterval = 0.15,
        rateLimitBackoff: TimeInterval = 5
    ) {
        self.cache = cache ?? CacheManager.shared
        self.geocoder = geocoder ?? MapKitGeocoder()
        self.requestDelay = requestDelay
        self.rateLimitBackoff = rateLimitBackoff
    }

    /// Process addresses for geocoding. If `userLocation` is provided, cached contacts are
    /// delivered nearest-first so nearby pins appear on the map before distant ones.
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil) {
        runID += 1
        let run = runID
        summary = Summary()

        var resolvedHits: [MappedContact] = []
        var cacheMisses: [Job] = []
        var refreshes: [Job] = []

        for address in addresses {
            // Single lookup per address (no double lookup)
            let cached = cache.coordinate(for: address.addressString)

            if let cached, !cached.failed {
                resolvedHits.append(mappedContact(address, at: cached.coordinate))
                summary.resolvedFromCache += 1
                continue
            }

            if cached?.failed == true {
                // Legacy failure entry from an older build. Never skip it — a transient
                // failure must not hide a contact until the entry expires.
                summary.retriedCachedFailures += 1
            } else if let expired = cache.expiredCoordinate(for: address.addressString) {
                // The address hasn't changed, so its old coordinate is almost certainly still
                // right. Show it now rather than hiding the pin until a throttled re-geocode lands.
                resolvedHits.append(mappedContact(address, at: expired.coordinate))
                summary.resolvedFromExpiredCache += 1
                refreshes.append(Job(address: address, isRefresh: true))
                continue
            }

            cacheMisses.append(Job(address: address, isRefresh: false))
        }

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

        // Contacts with no pin go first; refreshes only matter once they've all been tried.
        let jobs = cacheMisses + refreshes
        guard !jobs.isEmpty else {
            finish()
            return
        }

        geocodeSequentially(jobs: jobs, index: 0, attempt: 0, run: run)
    }

    /// Forgets cached locations for addresses no longer in the user's contacts.
    /// - Parameter addresses: A complete, successful fetch — never a partial one.
    func forgetAddresses(notIn addresses: [ContactsManager.RawContactAddress]) {
        cache.retainOnly(Set(addresses.map(\.addressString)))
        cache.saveToDisk()
    }

    func cancel() {
        runID += 1
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
        FromExpiredCache: \(summary.resolvedFromExpiredCache) (refreshed: \(summary.refreshedExpired)), \
        Geocoded: \(summary.geocoded), \
        Failed: \(summary.failed) (invalid: \(summary.invalidAddressStrings)), \
        RetriedCachedFailures: \(summary.retriedCachedFailures)
        """)
        #endif
    }

    private func mappedContact(_ address: ContactsManager.RawContactAddress, at coordinate: CLLocationCoordinate2D) -> MappedContact {
        MappedContact(
            contactID: address.contactID,
            fullName: address.fullName,
            addressLabel: address.addressLabel,
            addressString: address.addressString,
            coordinate: coordinate,
            thumbnailImageData: address.thumbnailImageData,
            phoneNumber: address.phoneNumber
        )
    }

    /// - Parameter attempt: How many times `jobs[index]` has already been throttled.
    private func geocodeSequentially(jobs: [Job], index: Int, attempt: Int, run: Int) {
        var index = index
        var attempt = attempt

        while true {
            // A newer run (or a cancel) took over; this one stops without reporting.
            guard run == runID else { return }

            guard index < jobs.count else {
                cache.saveToDisk()
                finish()
                return
            }

            let job = jobs[index]
            let completed = index + 1

            // A geocoder that calls back before `geocode` returns advances this loop instead
            // of recursing, so a 1000-address run doesn't build a 1000-frame stack. The
            // production geocoder is asynchronous and takes the scheduled path below.
            var isCallbackOnStack = true
            var advanceInLoop: (index: Int, attempt: Int)?

            geocoder.geocode(job.address.addressString) { [weak self] outcome in
                // Cancelling doesn't stop a response already on its way; drop it.
                guard let self, run == self.runID else { return }

                let next: (index: Int, attempt: Int, delay: TimeInterval)
                if case .rateLimited = outcome, !job.isRefresh, attempt < Self.maxRateLimitRetries {
                    // Throttled: wait it out and retry the same address.
                    next = (index, attempt + 1, self.rateLimitBackoff * pow(2, Double(attempt)))
                } else {
                    self.record(outcome: outcome, for: job)
                    self.onProgress?(completed, jobs.count)

                    // Persist every 10 geocodes to protect progress if the app is killed
                    if completed % 10 == 0 {
                        self.cache.saveToDisk()
                    }
                    // Delay before next geocode to respect Apple rate limits
                    next = (completed, 0, self.requestDelay)
                }

                guard next.delay > 0 else {
                    if isCallbackOnStack {
                        advanceInLoop = (next.index, next.attempt)
                    } else {
                        self.geocodeSequentially(jobs: jobs, index: next.index, attempt: next.attempt, run: run)
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + next.delay) { [weak self] in
                    self?.geocodeSequentially(jobs: jobs, index: next.index, attempt: next.attempt, run: run)
                }
            }

            isCallbackOnStack = false

            // The callback scheduled the next step itself; this walk is done here.
            guard let step = advanceInLoop else { return }
            index = step.index
            attempt = step.attempt
        }
    }

    private func record(outcome: GeocodeOutcome, for job: Job) {
        let address = job.address

        switch outcome {
        case .success(let coordinate) where coordinate.isPlottable:
            let cached = CachedCoordinate(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                cachedAt: Date()
            )
            cache.store(coordinate: cached, for: address.addressString)

            if job.isRefresh {
                // Already on the map at the expired coordinate; the new one is used next launch.
                summary.refreshedExpired += 1
                return
            }
            summary.geocoded += 1
            onContactResolved?(mappedContact(address, at: coordinate))

        case _ where job.isRefresh:
            // The pin is already showing its last known location. Keep the expired entry
            // and try again next launch.
            break

        case .success:
            // NaN or out-of-range coordinate: unplottable, and NaN would make the cache
            // file unencodable. Treat it like any other failed geocode.
            summary.failed += 1
            #if DEBUG
            print("[GeocodingManager] Invalid coordinate for '\(address.addressString)'")
            #endif

        case .invalidAddress:
            // Deliberately NOT cached as a failure: constructing the request is free
            // (no network call) and can fail for valid addresses due to formatting or
            // encoding quirks. Retry on the next launch.
            summary.failed += 1
            summary.invalidAddressStrings += 1
            #if DEBUG
            print("[GeocodingManager] Invalid address string: '\(address.addressString)'")
            #endif

        case .rateLimited:
            // Still throttled after every retry. Not cached — retry next launch.
            summary.failed += 1
            #if DEBUG
            print("[GeocodingManager] Rate limited, giving up for now: '\(address.addressString)'")
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

private extension CachedCoordinate {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
