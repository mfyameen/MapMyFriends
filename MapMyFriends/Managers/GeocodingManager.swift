//
//  GeocodingManager.swift
//  MapMyFriends
//

import MapKit

class GeocodingManager {

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    var onComplete: (() -> Void)?

    private let cache: CacheManaging
    private var isCancelled = false
    private var currentRequest: MKGeocodingRequest?

    init(cache: CacheManaging = CacheManager.shared) {
        self.cache = cache
    }

    func process(addresses: [ContactsManager.RawContactAddress]) {
        isCancelled = false

        var cacheHits: [ContactsManager.RawContactAddress] = []
        var cacheMisses: [ContactsManager.RawContactAddress] = []

        for address in addresses {
            if cache.coordinate(for: address.addressString) != nil {
                cacheHits.append(address)
            } else {
                cacheMisses.append(address)
            }
        }

        // Deliver cache hits immediately
        for address in cacheHits {
            if let cached = cache.coordinate(for: address.addressString) {
                let contact = MappedContact(
                    contactID: address.contactID,
                    fullName: address.fullName,
                    addressLabel: address.addressLabel,
                    addressString: address.addressString,
                    coordinate: CLLocationCoordinate2D(latitude: cached.lat, longitude: cached.lng),
                    thumbnailImageData: address.thumbnailImageData
                )
                onContactResolved?(contact)
            }
        }

        // Process cache misses sequentially
        guard !cacheMisses.isEmpty else {
            onComplete?()
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
            onComplete?()
            return
        }

        let address = addresses[index]

        guard let request = MKGeocodingRequest(addressString: address.addressString) else {
            print("[GeocodingManager] Invalid address string: '\(address.addressString)'")
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
                    thumbnailImageData: address.thumbnailImageData
                )
                self.onContactResolved?(contact)
            } else {
                print("[GeocodingManager] Failed to geocode '\(address.addressString)': \(error?.localizedDescription ?? "no results")")
            }

            self.onProgress?(index + 1, total)

            // Delay before next geocode to respect Apple rate limits
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.geocodeSequentially(addresses: addresses, index: index + 1, total: total)
            }
        }
    }
}
