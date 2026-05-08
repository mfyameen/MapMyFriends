# Map My Friends 📍

An iOS app that reads your phone contacts, geocodes their addresses, and plots them as clustered pins on a full-screen map. Your location is shown as a blue dot. Tap a pin to see the contact's name and address type. All geocoding results are cached locally so subsequent launches are near-instant.

**No third-party dependencies.** Built entirely with Apple frameworks.

## Screenshots

<!-- Add screenshots here -->

## Features

- **Contact mapping** — Automatically reads contacts with postal addresses and plots them on a map
- **Smart caching** — Geocoded coordinates are persisted to a local JSON file; second launch loads instantly with no network calls
- **Pin clustering** — MapKit's native clustering groups nearby pins and shows a count badge at lower zoom levels
- **Progressive loading** — A bottom banner shows real-time progress as addresses are geocoded ("Mapping 12 of 47 contacts…")
- **User location** — Blue dot shows your current position; map centers on you at launch
- **Callout details** — Tap any pin to see the contact's full name, address label (Home/Work/Other), and address

## Requirements

- iOS 26.0+
- Xcode 26+
- Swift 5.9+
- No third-party dependencies

## Getting Started

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/MapMyFriends.git
   ```
2. Open `MapMyFriends.xcodeproj` in Xcode
3. Select a development team under **Signing & Capabilities**
4. Build and run on a simulator or device

The app will prompt for Contacts and Location permissions on first launch.

## Architecture

```
MapMyFriends/
├── MapMyFriendsApp.swift          # SwiftUI app entry point
├── Controllers/
│   └── MapViewController.swift    # Root UIKit VC — map, location, orchestration
├── Managers/
│   ├── CacheManager.swift         # JSON cache with CacheManaging protocol
│   ├── ContactsManager.swift      # Contacts permission & fetch
│   └── GeocodingManager.swift     # Sequential geocoding with rate limiting
├── Models/
│   ├── MappedContact.swift        # Contact + coordinate
│   └── CachedCoordinate.swift     # Codable lat/lng/timestamp
├── Views/
│   ├── ContactAnnotation.swift    # MKAnnotation wrapper
│   ├── ContactAnnotationView.swift # Blue person pin with clustering
│   ├── ClusterAnnotationView.swift # Circle with count badge
│   └── MapViewControllerWrapper.swift # UIViewControllerRepresentable bridge
└── Assets.xcassets/
```

### Key Design Decisions

- **SwiftUI lifecycle, UIKit map** — The app uses `MapMyFriendsApp.swift` as the entry point but hosts a UIKit `MapViewController` via `UIViewControllerRepresentable`. This gives us full `MKMapView` delegate control while keeping the modern app lifecycle.
- **Swift 6 strict concurrency** — `MainActor` default isolation is enabled. Background work (contact fetching) uses `nonisolated` and `@Sendable` closures.
- **Protocol-based caching** — `CacheManager` conforms to `CacheManaging` and accepts a custom file URL, making it fully testable with isolated temp files.
- **Dependency injection** — `GeocodingManager` accepts a `CacheManaging` instance (defaults to `CacheManager.shared`), enabling mock injection in tests.
- **Batch cache saves** — The cache writes to disk once after all geocoding completes (or on cancel), not after every individual store, reducing disk I/O.
- **Sequential geocoding with delay** — Addresses are geocoded one at a time with a 0.15s delay between requests to stay well under Apple's `MKGeocodingRequest` rate limit.

## How It Works

1. **Launch** → `MapViewController` requests contacts permission
2. **Fetch** → `ContactsManager` enumerates all contacts with postal addresses on a background thread
3. **Cache check** → `GeocodingManager` separates addresses into cache hits (instant) and misses (need geocoding)
4. **Geocode** → Cache misses are geocoded sequentially via `MKGeocodingRequest` with rate-limit delays
5. **Plot** → Each resolved contact is added to the map as a `ContactAnnotation` in real-time
6. **Persist** → On completion, the cache is written to disk for instant loading on next launch

## Tests

The project includes 27 unit and integration tests using Swift Testing framework.

```
MapMyFriendsTests/
├── Mocks/
│   └── MockCacheManager.swift
├── CachedCoordinateTests.swift      # Codable round-trip, JSON stability, date precision
├── CacheManagerTests.swift          # Store/retrieve, overwrite, persistence, corrupt recovery
├── ContactAnnotationTests.swift     # Title, subtitle format, coordinate passthrough
├── GeocodingManagerTests.swift      # Cache hits, empty input, cancel, metadata preservation
├── AnnotationViewTests.swift        # Pin configuration, cluster view layout
└── CacheIntegrationTests.swift      # End-to-end persistence, concurrent reads
```

Run tests:
```
xcodebuild -scheme MapMyFriendsTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Roadmap

- [ ] Contact change detection — re-geocode when `CNContactStoreDidChangeNotification` fires
- [ ] Cache invalidation — detect when a cached address no longer matches the contact's current address
- [ ] Refresh button — nav bar button to manually re-fetch and re-geocode
- [ ] Error state UI — surface geocoding failure count ("3 addresses could not be mapped")
- [ ] Contact avatar pins — circular contact photo instead of marker pins
- [ ] Address type color coding — different pin colors for Home vs Work vs Other

## License

<!-- Add your license here -->
