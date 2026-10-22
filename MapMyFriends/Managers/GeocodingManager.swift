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
        /// Subset of `failed` skipped without a request: Apple Maps recently said it can't find them.
        var skippedNotFound = 0
        /// Every address that didn't make it onto the map this run, and why.
        var unmapped: [UnmappedContact] = []

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

    /// One lookup: an address string and every contact who has it (coworkers, family), so a
    /// shared address costs one request against Apple's rate limit, not one per person.
    /// A refresh already has its pins (from an expired cache entry), so its result only
    /// updates the cache.
    private struct Job {
        let addresses: [ContactsManager.RawContactAddress]
        let isRefresh: Bool

        var addressString: String { addresses[0].addressString }
    }

    /// The lookups for one run, plus how many contacts are done after each, so progress
    /// reads "Mapping N of M contacts" rather than counting lookups.
    private struct Plan {
        let jobs: [Job]
        let contactsDoneAfter: [Int]
        var totalContacts: Int { contactsDoneAfter.last ?? 0 }

        init(_ jobs: [Job]) {
            self.jobs = jobs
            var running = 0
            contactsDoneAfter = jobs.map { running += $0.addresses.count; return running }
        }
    }

    private let cache: CacheManaging
    private let geocoder: AddressGeocoding
    /// Pause between geocodes to respect Apple rate limits. Tests set this to 0 to run synchronously.
    private let requestDelay: TimeInterval
    /// Base wait after Apple throttles a request; doubles on each consecutive throttle.
    private let rateLimitBackoff: TimeInterval
    /// The pause between lookups once Apple has throttled this run.
    private let throttledRequestDelay: TimeInterval
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
        rateLimitBackoff: TimeInterval = 5,
        throttledRequestDelay: TimeInterval = 1.3
    ) {
        self.cache = cache ?? CacheManager.shared
        self.geocoder = geocoder ?? MapKitGeocoder()
        self.requestDelay = requestDelay
        self.rateLimitBackoff = rateLimitBackoff
        self.throttledRequestDelay = throttledRequestDelay
        self.currentRequestDelay = requestDelay
    }

    /// The pause between lookups right now: `requestDelay`, until Apple throttles this run.
    private(set) var currentRequestDelay: TimeInterval

    /// Process addresses for geocoding. If `userLocation` is provided, cached contacts are
    /// delivered nearest-first so nearby pins appear on the map before distant ones.
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil) {
        runID += 1
        let run = runID
        summary = Summary()
        // Apple's throttle is a short window; a new run (an edit, a foreground) starts fast again.
        currentRequestDelay = requestDelay

        var resolvedHits: [MappedContact] = []
        var cacheMisses: [ContactsManager.RawContactAddress] = []
        var refreshes: [ContactsManager.RawContactAddress] = []

        for address in addresses {
            // Single lookup per address (no double lookup)
            let cached = cache.coordinate(for: address.addressString)

            if cached?.notFound == true {
                // Apple Maps recently said this address doesn't exist; asking again would only
                // spend rate-limit budget. Tried again once the entry expires.
                summary.failed += 1
                summary.skippedNotFound += 1
                summary.unmapped.append(unmapped(address, .addressNotFound))
                continue
            }

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
                refreshes.append(address)
                continue
            }

            cacheMisses.append(address)
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
        let plan = Plan(Self.grouped(cacheMisses, isRefresh: false) + Self.grouped(refreshes, isRefresh: true))
        guard !plan.jobs.isEmpty else {
            finish()
            return
        }

        geocodeSequentially(plan: plan, index: 0, attempt: 0, run: run)
    }

    /// Forgets cached locations for addresses no longer in the user's contacts.
    /// - Parameter addresses: A complete, successful fetch — never a partial one.
    func forgetAddresses(notIn addresses: [ContactsManager.RawContactAddress]) {
        // Runs on every refresh; only rewrite the file when something actually went.
        if cache.retainOnly(Set(addresses.map(\.addressString))) > 0 {
            cache.saveToDisk()
        }
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
        Failed: \(summary.failed) (invalid: \(summary.invalidAddressStrings), known not found: \(summary.skippedNotFound)), \
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

    private func unmapped(_ address: ContactsManager.RawContactAddress, _ reason: UnmappedContact.Reason) -> UnmappedContact {
        UnmappedContact(contactID: address.contactID, fullName: address.fullName, addressString: address.addressString, reason: reason)
    }

    /// One job per distinct address string, in first-seen order.
    private static func grouped(_ addresses: [ContactsManager.RawContactAddress], isRefresh: Bool) -> [Job] {
        var order: [String] = []
        var byAddress: [String: [ContactsManager.RawContactAddress]] = [:]
        for address in addresses {
            if byAddress[address.addressString] == nil {
                order.append(address.addressString)
            }
            byAddress[address.addressString, default: []].append(address)
        }
        return order.compactMap { key in byAddress[key].map { Job(addresses: $0, isRefresh: isRefresh) } }
    }

    /// - Parameter attempt: How many times `plan.jobs[index]` has already been throttled.
    private func geocodeSequentially(plan: Plan, index: Int, attempt: Int, run: Int) {
        var index = index
        var attempt = attempt

        while true {
            // A newer run (or a cancel) took over; this one stops without reporting.
            guard run == runID else { return }

            guard index < plan.jobs.count else {
                cache.saveToDisk()
                finish()
                return
            }

            let job = plan.jobs[index]
            let completed = index + 1

            // A geocoder that calls back before `geocode` returns advances this loop instead
            // of recursing, so a 1000-address run doesn't build a 1000-frame stack. The
            // production geocoder is asynchronous and takes the scheduled path below.
            var isCallbackOnStack = true
            var advanceInLoop: (index: Int, attempt: Int)?

            geocoder.geocode(job.addressString) { [weak self] outcome in
                // Cancelling doesn't stop a response already on its way; drop it.
                guard let self, run == self.runID else { return }

                if case .rateLimited = outcome {
                    // Apple's limit applies to every lookup, not just this one: slow the rest of
                    // the run to roughly that limit instead of re-tripping it at full speed.
                    if self.currentRequestDelay < self.throttledRequestDelay {
                        self.currentRequestDelay = self.throttledRequestDelay
                        #if DEBUG
                        print("[GeocodingManager] Throttled; slowing to one lookup per \(self.throttledRequestDelay)s for this run")
                        #endif
                    }
                }

                let next: (index: Int, attempt: Int, delay: TimeInterval)
                if case .rateLimited = outcome, !job.isRefresh, attempt < Self.maxRateLimitRetries {
                    // Throttled: wait it out and retry the same address.
                    next = (index, attempt + 1, self.rateLimitBackoff * pow(2, Double(attempt)))
                } else {
                    self.record(outcome: outcome, for: job)
                    self.onProgress?(plan.contactsDoneAfter[index], plan.totalContacts)

                    // Persist every 10 geocodes to protect progress if the app is killed
                    if completed % 10 == 0 {
                        self.cache.saveToDisk()
                    }
                    // Delay before next geocode to respect Apple rate limits
                    next = (completed, 0, self.currentRequestDelay)
                }

                guard next.delay > 0 else {
                    if isCallbackOnStack {
                        advanceInLoop = (next.index, next.attempt)
                    } else {
                        self.geocodeSequentially(plan: plan, index: next.index, attempt: next.attempt, run: run)
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + next.delay) { [weak self] in
                    self?.geocodeSequentially(plan: plan, index: next.index, attempt: next.attempt, run: run)
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
        let addressString = job.addressString

        switch outcome {
        case .success(let coordinate) where coordinate.isPlottable:
            let cached = CachedCoordinate(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                cachedAt: Date()
            )
            cache.store(coordinate: cached, for: addressString)

            if job.isRefresh {
                // Already on the map at the expired coordinate; the new one is used next launch.
                summary.refreshedExpired += job.addresses.count
                return
            }
            for address in job.addresses {
                summary.geocoded += 1
                onContactResolved?(mappedContact(address, at: coordinate))
            }

        case _ where job.isRefresh:
            // The pins are already showing their last known location. Keep the expired entry
            // and try again next launch.
            break

        case .success:
            // NaN or out-of-range coordinate: unplottable, and NaN would make the cache
            // file unencodable. Treat it like any other failed geocode.
            reportUnmapped(job, .addressNotFound)
            #if DEBUG
            print("[GeocodingManager] Invalid coordinate for '\(addressString)'")
            #endif

        case .invalidAddress:
            // Deliberately NOT cached as a failure: constructing the request is free
            // (no network call) and can fail for valid addresses due to formatting or
            // encoding quirks. Retry on the next launch.
            summary.invalidAddressStrings += job.addresses.count
            reportUnmapped(job, .addressNotFound)
            #if DEBUG
            print("[GeocodingManager] Invalid address string: '\(addressString)'")
            #endif

        case .notFound:
            cache.store(
                coordinate: CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), notFound: true),
                for: addressString
            )
            reportUnmapped(job, .addressNotFound)
            #if DEBUG
            print("[GeocodingManager] Not found, won't retry for a day: '\(addressString)'")
            #endif

        case .rateLimited:
            // Still throttled after every retry. Not cached — retry next launch.
            reportUnmapped(job, .couldNotConnect)
            #if DEBUG
            print("[GeocodingManager] Rate limited, giving up for now: '\(addressString)'")
            #endif

        case .failed(let reason):
            // Deliberately NOT cached as a failure. A transient network error or rate limit
            // must not hide this contact until a cache entry expires — retry next launch.
            reportUnmapped(job, .couldNotConnect)
            #if DEBUG
            print("[GeocodingManager] Failed to geocode '\(addressString)': \(reason ?? "no results")")
            #endif
        }
    }

    /// Every contact sharing the job's address failed together.
    private func reportUnmapped(_ job: Job, _ reason: UnmappedContact.Reason) {
        for address in job.addresses {
            summary.failed += 1
            summary.unmapped.append(unmapped(address, reason))
        }
    }
}

private extension CachedCoordinate {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
