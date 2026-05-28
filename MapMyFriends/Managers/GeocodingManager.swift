//
//  GeocodingManager.swift
//  MapMyFriends
//

import MapKit

@MainActor
class GeocodingManager {

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Called when all geocoding is finished. Parameter is the number of addresses that failed to geocode.
    var onComplete: ((Int) -> Void)?

    private let cache: CacheManaging
    private var isCancelled = false
    private var currentRequest: MKGeocodingRequest?
    private var failedCount = 0

    init(cache: CacheManaging = CacheManager.shared) {
        self.cache = cache
    }

    /// Process addresses for geocoding. If `userLocation` is provided, cached contacts are
    /// delivered nearest-first so nearby pins appear on the map before distant ones.
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil) {
        isCancelled = false
        failedCount = 0

        var cacheHits: [ContactsManager.RawContactAddress] = []
        var cacheMisses: [ContactsManager.RawContactAddress] = []

        for address in addresses {
            if let cached = cache.coordinate(for: address.addressString) {
                if cached.failed {
                    // Previously failed — skip silently, TTL will retry later
                    continue
                }
                cacheHits.append(address)
            } else {
                cacheMisses.append(address)
            }
        }

        // Resolve cache hits into MappedContacts
        var resolvedHits: [MappedContact] = []
        for address in cacheHits {
            if let cached = cache.coordinate(for: address.addressString) {
                resolvedHits.append(MappedContact(
                    contactID: address.contactID,
                    fullName: address.fullName,
                    addressLabel: address.addressLabel,
                    addressString: address.addressString,
                    coordinate: CLLocationCoordinate2D(latitude: cached.lat, longitude: cached.lng),
                    thumbnailImageData: address.thumbnailImageData,
                    phoneNumber: address.phoneNumber
                ))
            }
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

        // Process cache misses sequentially
        guard !cacheMisses.isEmpty else {
            onComplete?(0)
            return
        }

        geocodeSequentially(addresses: cacheMisses, index: 0, total: cacheMisses.count)
    }

    func cancel() {
        isCancelled = true
        currentRequest?.cancel()
        currentRequest = nil
        cache.saveToDisk()
    }

    // MARK: - Private

    private func geocodeSequentially(addresses: [ContactsManager.RawContactAddress], index: Int, total: Int) {
        guard !isCancelled, index < addresses.count else {
            cache.saveToDisk()
            onComplete?(failedCount)
            return
        }

        let address = addresses[index]

        guard let request = MKGeocodingRequest(addressString: address.addressString) else {
            #if DEBUG
            print("[GeocodingManager] Invalid address string: '\(address.addressString)'")
            #endif
            onProgress?(index + 1, total)
            geocodeSequentially(addresses: addresses, index: index + 1, total: total)
            return
        }

        currentRequest = request

        request.getMapItems { [weak self] mapItems, error in
            guard let self, !self.isCancelled else { return }

            if let coordinate = mapItems?.first?.location.coordinate {
                let cached = CachedCoordinate(
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    cachedAt: Date()
                )
                cache.store(coordinate: cached, for: address.addressString)

                let contact = MappedContact(
                    contactID: address.contactID,
                    fullName: address.fullName,
                    addressLabel: address.addressLabel,
                    addressString: address.addressString,
                    coordinate: coordinate,
                    thumbnailImageData: address.thumbnailImageData,
                    phoneNumber: address.phoneNumber
                )
                self.onContactResolved?(contact)
            } else {
                self.failedCount += 1
                // Cache the failure so we don't retry on every launch (TTL will retry later)
                let failedEntry = CachedCoordinate(lat: 0, lng: 0, cachedAt: Date(), failed: true)
                cache.store(coordinate: failedEntry, for: address.addressString)
                #if DEBUG
                print("[GeocodingManager] Failed to geocode '\(address.addressString)': \(error?.localizedDescription ?? "no results")")
                #endif
            }

            let completed = index + 1
            self.onProgress?(completed, total)

            // Persist every 10 geocodes to protect progress if the app is killed
            if completed % 10 == 0 {
                cache.saveToDisk()
            }

            // Delay before next geocode to respect Apple rate limits
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.geocodeSequentially(addresses: addresses, index: index + 1, total: total)
            }
        }
    }
}
