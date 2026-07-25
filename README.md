# Map My Friends 📍

An iOS app that reads your phone contacts, geocodes their addresses, and plots them as clustered pins on a full-screen map. Your location is shown as a blue dot. Tap a pin to see the contact's name and address type. All geocoding results are cached locally so subsequent launches are near-instant.

Made lovingly by @mfyameen with AI
Entirely open-source
Code available at https://github.com/mfyameen/MapMyFriends

**No third-party dependencies.** Built entirely with Apple frameworks.

## Screenshots

<!-- Add screenshots here -->

## Features

- **Contact mapping** — Automatically reads contacts with postal addresses and plots them on a map
- **Smart caching** — Geocoded coordinates are persisted to a local JSON file with 90-day TTL; subsequent launches load instantly
- **Failed geocode handling** — Transient geocoding failures are cached with a 24-hour TTL and retried automatically
- **Pin clustering** — MapKit's native clustering groups nearby pins; tapping a cluster zooms in to reveal members
- **Same-location clusters** — When contacts share an address, tapping the cluster shows a list instead of zooming further
- **User location** — Blue dot shows your current position; map centers on you at launch with a tracking button to recenter
- **Proximity sorting** — Cached contacts are delivered nearest-first so nearby pins appear on the map before distant ones
- **Callout actions** — Tap any pin to open the contact in the Contacts app, or (via Settings) show Call/Message options
- **Live contact sync** — Listens for `CNContactStoreDidChange` and diffs contacts to add/remove only changed pins
- **Incremental persistence** — Cache saves to disk every 10 geocodes to protect progress if the app is killed mid-run
- **About page** — Info button in the nav bar opens an About page with app description and GitHub link
- **Feature flags** — User-facing settings in iOS Settings app to toggle pin tap behavior and progress display

## Requirements

- iOS 26.0+
- Xcode 26+
- Swift 5.9+
- No third-party dependencies

## Getting Started

1. Clone the repository:
   ```
   git clone https://github.com/mfyameen/MapMyFriends.git
   ```
2. Open `MapMyFriends.xcodeproj` in Xcode
3. Select a development team under **Signing & Capabilities**
4. Build and run on a simulator or device

The app will prompt for Contacts and Location permissions on first launch.

## Architecture

```
MapMyFriends/
├── MapMyFriendsApp.swift            # SwiftUI app entry point, registers FeatureFlags defaults
├── FeatureFlags.swift               # UserDefaults-backed feature flags (Settings.bundle)
├── Controllers/
│   └── MapViewController.swift      # Root UIKit VC — map, location, clustering, contact actions
├── Managers/
│   ├── CacheManager.swift           # JSON cache with dual TTL (90d success, 24h failed)
│   ├── ContactsManager.swift        # Contacts permission & fetch (incl. thumbnails & phone numbers)
│   ├── ContactDiffer.swift          # Pure-function diff for live contact sync
│   └── GeocodingManager.swift       # Sequential geocoding with failure caching & proximity sort
├── Models/
│   ├── MappedContact.swift          # Contact + coordinate + thumbnail + phone number
│   └── CachedCoordinate.swift       # Codable lat/lng/timestamp/failed flag
├── Views/
│   ├── AboutView.swift              # SwiftUI About page with app icon & GitHub link
│   ├── ContactAnnotation.swift      # MKAnnotation wrapper
│   ├── ContactAnnotationView.swift  # Blue person pin with reuse-safe styling
│   ├── ClusterAnnotationView.swift  # Circle with count badge
│   └── MapViewControllerWrapper.swift # UIViewControllerRepresentable bridge
├── Settings.bundle/                 # iOS Settings app toggles for feature flags
└── Assets.xcassets/                 # App icon, GitHub logo (light/dark)
```

### Key Design Decisions

- **SwiftUI lifecycle, UIKit map** — `MapMyFriendsApp.swift` as the entry point hosts a UIKit `MapViewController` via `UIViewControllerRepresentable`, giving full `MKMapView` delegate control.
- **Swift 6 strict concurrency** — `MainActor` default isolation is enabled. Background work uses `nonisolated` and `@Sendable` closures.
- **Protocol-based caching** — `CacheManager` conforms to `CacheManaging` with injectable file URL and TTLs, enabling fully isolated testing.
- **Dual TTL strategy** — Successful geocodes expire after 90 days; failed geocodes use a 24-hour TTL for faster retry of transient errors.
- **Single cache lookup** — `GeocodingManager` resolves contacts directly from the first cache lookup, eliminating a previous double-lookup race condition.
- **Incremental persistence** — Cache saves to disk every 10 geocodes during sequential processing, protecting partial progress.
- **Sequential geocoding with delay** — Addresses are geocoded one at a time with a 0.15s delay to stay under Apple's rate limit.
- **Contact diffing** — `ContactDiffer` computes a minimal diff (using `contactID + addressString` as identity) to add/remove only changed pins.
- **Reuse-safe annotation views** — `ContactAnnotationView` re-applies styling in `init`, `prepareForReuse`, and `annotation didSet` to prevent red pin artifacts during cluster transitions.
- **Feature flags via Settings.bundle** — User-facing toggles backed by `UserDefaults` for pin tap behavior and progress display.

## How It Works

1. **Launch** → `MapMyFriendsApp` registers feature flag defaults; `MapViewController` requests contacts permission and subscribes to `CNContactStoreDidChange`
2. **Fetch** → `ContactsManager` enumerates all contacts with postal addresses, thumbnails, and phone numbers on a background thread
3. **Cache check** → `GeocodingManager` classifies each address in a single lookup: cache hit (resolve immediately), failed entry (skip, retry after 24h), or cache miss (geocode)
4. **Sort** → Cache hits are sorted by proximity to user location so nearby pins appear first
5. **Geocode** → Cache misses are geocoded sequentially via `MKGeocodingRequest` with 0.15s delays; failures are cached with a 24h TTL
6. **Plot** → Each resolved contact is added to the map as a `ContactAnnotation`; clusters auto-zoom on tap
7. **Persist** → Cache saves incrementally every 10 geocodes, plus a final save on completion
8. **Live sync** → When contacts change, `ContactDiffer` computes a minimal diff and only adds/removes affected pins

## Tests

The project includes 91 tests using the Swift Testing framework.

```
MapMyFriendsTests/
├── Mocks/
│   └── MockCacheManager.swift
├── CachedCoordinateTests.swift          # Codable round-trip, JSON stability, failed field
├── CacheManagerTests.swift              # Store/retrieve, TTL expiry, failed entry persistence
├── CacheManagerThreadSafetyTests.swift  # Concurrent read/write stress tests
├── CacheIntegrationTests.swift          # End-to-end persistence, concurrent reads
├── ContactAnnotationTests.swift         # Title, subtitle, coordinate, phone number passthrough
├── ContactDifferTests.swift             # Diff logic for live contact sync
├── ContactPlottingTests.swift           # Comprehensive pipeline tests (22 cases)
├── GeocodingManagerTests.swift          # Cache hits, failures, proximity sort, metadata
├── AnnotationViewTests.swift            # Pin styling, reuse safety, cluster view layout
├── FeatureFlagsTests.swift              # UserDefaults-backed flag reads, overrides
└── NoDataExfiltrationTests.swift        # Verifies no sensitive data leaks
```

Run tests:
```
xcodebuild -scheme MapMyFriends -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Settings

User-configurable options are available in **iOS Settings → Map My Friends**:

- **Open Contact on Tap** — When on, tapping a pin opens the contact in the Contacts app. When off, shows Call/Message options. *(default: off)*
- **Hide Mapping Progress** — When on, suppresses the geocoding progress banner and error toast. *(default: on)*

## Roadmap

- [x] Contact change detection — live sync via `CNContactStoreDidChange` + `ContactDiffer`
- [x] Contact avatar pins — *(disabled pending fix — see TODO in `ContactAnnotationView`)*
- [x] Error state UI — geocoding failure count toast ("3 addresses could not be mapped")
- [x] Cache TTL — 90-day expiry for successful entries, 24-hour for failed
- [x] Incremental persistence — save every 10 geocodes
- [x] Proximity sorting — nearest contacts appear first
- [x] Call/Text from pin — action sheet with Call/Message (feature-flagged)
- [x] Open in Contacts — push `CNContactViewController` from pin tap (feature-flagged)
- [x] About page — app info and GitHub link
- [x] Feature flags — Settings.bundle with user-facing toggles
- [x] Cluster zoom — tap cluster to zoom in; same-location clusters show contact list
- [ ] Cache invalidation — detect when a cached address no longer matches the contact's current address
- [ ] Refresh button — nav bar button to manually re-fetch and re-geocode
- [ ] Address type color coding — different pin colors for Home vs Work vs Other
- [ ] Fix contact avatar on pins — disabled due to rendering issues

## License

<!-- MIT license -->
