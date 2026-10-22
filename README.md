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
- **Smart caching** — Successful geocodes are persisted to a local JSON file with a 90-day TTL; subsequent launches load instantly. The file lives in Application Support, is excluded from backups, and drops addresses that are no longer in your contacts
- **Failures are never cached** — A transient network error, rate limit, or unparseable address is retried when the app next returns to the foreground (or relaunches) instead of hiding the contact
- **Rate-limit backoff** — When Apple throttles geocoding, the same address is retried with exponential backoff instead of being dropped, so a first launch with hundreds of contacts maps all of them
- **Expired entries stay visible** — A cache entry past its 90-day TTL still shows its pin immediately while a fresh geocode refreshes it in the background
- **Run summary** — Every geocoding pass logs a breakdown (from cache / geocoded / failed / retried) in DEBUG, even when progress toasts are hidden
- **Contact photo pins** — Contacts with a photo appear as their circular photo in a white ring, with their name underneath like the blue markers; everyone else gets the blue person marker. Both kinds cluster together
- **Pin clustering** — MapKit's native clustering groups nearby pins; tapping a cluster zooms in to reveal members
- **Same-location clusters** — When contacts share an address, or the map is already zoomed all the way in, tapping the cluster lists every member, sorted by name, instead of zooming further
- **User location** — Blue dot shows your current position; map centers on you at launch with a tracking button to recenter. Location permission is asked for only after the pins are on the map, not alongside the Contacts prompt. After the launch view, or as soon as you pan or zoom, the map never moves on its own
- **Empty map card** — When no contact has an address, or Contacts access is off, a card says so instead of leaving a blank map (with Open Settings when access is off); with limited Contacts access it explains that only shared contacts are visible and opens Apple's in-app picker to share more (`ContactAccessPickerHost`), then reloads
- **Not on the map** — When some addresses couldn't be placed, a "N not on the map" button lists those contacts with the reason (address not found, or couldn't reach Apple Maps); tapping one opens it in Contacts, editable, so the address can be fixed
- **VoiceOver** — Pins read as name, label and address; clusters read as "N contacts" with a hint
- **Proximity sorting** — Cached contacts are delivered nearest-first so nearby pins appear on the map before distant ones
- **Callout actions** — Tap any pin to open the contact in the Contacts app, or (via Settings) show Call/Message options. Phone numbers are dialed properly: extensions after a pause ("555-1234 ext. 12" → `tel:5551234,12`), letters on the keypad (1-800-FLOWERS), digits from any script
- **Live contact sync** — Listens for `CNContactStoreDidChange` and diffs contacts to add/remove only changed pins; changes are debounced and deferred until the first geocoding pass finishes
- **Incremental persistence** — Cache saves to disk every 10 geocodes to protect progress if the app is killed mid-run
- **About page** — Info button in the nav bar opens an About page with app description and GitHub link
- **Feature flags** — User-facing settings in iOS Settings app to toggle pin tap behavior and progress display

## Requirements

- iOS 26.0+ (iPhone only)
- Xcode 26+
- Swift 5 language mode with main-actor-by-default isolation
- No third-party dependencies

## Getting Started

1. Clone the repository:
   ```
   git clone https://github.com/mfyameen/MapMyFriends.git
   ```
2. Open `MapMyFriends.xcodeproj` in Xcode
3. Select a development team under **Signing & Capabilities**
4. Build and run on a simulator or device

The app asks for Contacts permission on first launch, then for Location once your contacts are on the map.

## Architecture

```
MapMyFriends/
├── MapMyFriendsApp.swift            # SwiftUI app entry point, registers FeatureFlags defaults
├── FeatureFlags.swift               # UserDefaults-backed feature flags (Settings.bundle)
├── AppEnvironment.swift             # Detects when the app is hosting the unit tests
├── Controllers/
│   ├── MapDependencies.swift        # ContactFetching / LocationProviding seams for tests
│   └── MapViewController.swift      # Root UIKit VC — map, location, clustering, contact actions
├── Managers/
│   ├── AddressGeocoding.swift       # Geocoding protocol seam + MapKitGeocoder implementation
│   ├── CacheManager.swift           # Thread-safe JSON cache with 90-day TTL
│   ├── ClusterTapResolver.swift     # Decides whether a cluster tap zooms or lists its members
│   ├── ContactChangeCoalescer.swift # Gates/coalesces CNContactStoreDidChange notifications
│   ├── ContactsManager.swift        # Contacts permission & fetch (incl. thumbnails & phone numbers)
│   ├── ContactDiffer.swift          # Pure-function diff for live contact sync
│   ├── InitialCameraPolicy.swift    # When the map may move on its own
│   ├── PhoneDialer.swift            # tel:/sms: links: extensions, vanity letters, any-script digits
│   └── GeocodingManager.swift       # Sequential geocoding, run summary & proximity sort
├── Models/
│   ├── MappedContact.swift          # Contact + coordinate + thumbnail + phone number
│   ├── UnmappedContact.swift        # An address that isn't on the map, and why
│   └── CachedCoordinate.swift       # Codable lat/lng/timestamp (+ legacy failed flag)
├── Views/
│   ├── AboutView.swift              # SwiftUI About page with app icon & GitHub link
│   ├── ContactAnnotation.swift      # MKAnnotation wrapper
│   ├── ContactAnnotationView.swift  # Blue person pin with reuse-safe styling
│   ├── ContactPhotoAnnotationView.swift # Circular photo pin for contacts with a photo
│   ├── EmptyMapCardView.swift       # "No addresses yet" card over the map
│   ├── UnmappedContactsView.swift   # SwiftUI list behind the "N not on the map" button
│   ├── ContactAccessPickerHost.swift # Presents Apple's picker to share more contacts
│   ├── ContactPinViews.swift        # Registers the map's views and picks one per annotation
│   ├── ClusterAnnotationView.swift  # Circle with count badge
│   └── MapViewControllerWrapper.swift # UIViewControllerRepresentable bridge
├── PrivacyInfo.xcprivacy            # Privacy manifest (no tracking, no collected data)
├── Settings.bundle/                 # iOS Settings app toggles for feature flags
└── Assets.xcassets/                 # App icon, GitHub logo (light/dark)
```

### Key Design Decisions

- **SwiftUI lifecycle, UIKit map** — `MapMyFriendsApp.swift` as the entry point hosts a UIKit `MapViewController` via `UIViewControllerRepresentable`, giving full `MKMapView` delegate control.
- **Main-actor-by-default concurrency** — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency enabled. Background work uses `nonisolated` and `@Sendable` closures.
- **Protocol-based caching** — `CacheManager` conforms to `CacheManaging` with injectable file URL and TTLs, enabling fully isolated testing.
- **Failures are never persisted** — Only successful geocodes are cached. Caching failures previously hid contacts behind a single transient error; any legacy `failed: true` entry left on disk is now treated as a cache miss and retried.
- **Injectable geocoder** — `GeocodingManager` talks to an `AddressGeocoding` protocol (`MapKitGeocoder` in production, a mock in tests), so the whole pipeline can be exercised deterministically with no network access.
- **Single cache lookup** — `GeocodingManager` resolves contacts directly from the first cache lookup, eliminating a previous double-lookup race condition.
- **Incremental persistence** — Cache saves to disk every 10 geocodes during sequential processing, protecting partial progress.
- **Cache location** — `CacheManager.defaultFileURL()` is in Application Support, and every save sets `isExcludedFromBackup`. The cache can be rebuilt and holds every contact's address, so it follows Apple's data-storage guidance and doesn't survive in iCloud backups after the app is deleted. Builds that kept it in Documents are migrated on first launch (`migrateLegacyFile`), keeping the newer file if both exist.
- **Cache pruning** — After every complete, successful contact fetch, `GeocodingManager.forgetAddresses(notIn:)` drops cache entries for addresses no longer in Contacts, so a deleted contact's address doesn't linger on disk. Failed or denied fetches never prune.
- **The map moves on its own once** — `InitialCameraPolicy` allows one launch view: centered on the first location fix, or framing every contact when there's no location. Later geocoding runs (contact edits, foreground retries) never move the camera, and once the user pans, zooms, rotates or taps a cluster (`userDidMoveMap()`, fed by listen-only gesture recognizers) it never moves on its own at all. Location updates stop after the first fix; the map tracks the blue dot itself.
- **Fresh location only** — The newest fix in a batch is used, and only if it's under a minute old with a valid accuracy; iOS's cached last-known location (possibly another city) is ignored. A location denial stops updates.
- **Foreground retries are for retryable failures** — Returning to the app re-reads contacts only if a fetch failed or a lookup couldn't reach Apple Maps; addresses Apple Maps can't find are already remembered and skipped, so they don't trigger it.
- **Permission order** — `MapViewController` asks for Contacts at launch and for Location (`requestLocationIfNeeded()`) only once a complete contacts load has finished: after the first geocoding run, or straight away when there are no addresses. A denied or failed contacts fetch doesn't ask. If Location was granted on an earlier launch, setting the delegate starts updates without a prompt.
- **Unmapped report** — Every geocoding run returns `Summary.unmapped`: each address that didn't make it onto the map, with an `UnmappedContact.Reason`. The controller keeps them keyed like pins, drops them when they map or the contact is deleted, and shows the count and list.
- **Sequential geocoding with delay** — Addresses are geocoded one at a time with a 0.15s delay. The first time Apple throttles (`MKError.loadingThrottled`), the rest of that run slows to one lookup per 1.3s (about Apple's limit); the next run starts fast again. The throttled address itself is retried up to 4 times with exponential backoff (5s, 10s, 20s, 40s) before it is reported as failed for this run. The walk is a loop rather than per-address recursion, so a synchronous geocoder can't build a deep stack.
- **Runs are versioned** — Every `process()`/`cancel()` bumps a run ID. A geocode response or delayed step from a cancelled run is dropped, so a contact refresh can't resurrect deleted contacts, duplicate pins, or report completion twice.
- **Only plottable coordinates** — A NaN or out-of-range coordinate is treated as a failed geocode, and the cache refuses NaN (which would make the whole JSON file unencodable).
- **Unreadable cache is never clobbered** — If the cache file exists but can't be read (e.g. still locked by Data Protection), lookups retry the read and saves are skipped until it succeeds, so one bad launch can't wipe every cached location.
- **Deferred initial load** — Granting contacts permission fires `CNContactStoreDidChange` mid-geocode. `ContactChangeCoalescer` defers changes until the first pass completes, then collapses them into a single refresh, so the initial run is never cancelled part-way.
- **Failed fetch is not a deletion** — `ContactsManager` returns `.success`, `.denied`, or `.failed`. Only a complete, successful fetch is diffed; a denied or interrupted fetch leaves every pin alone, and a partial list is never passed off as the whole store.
- **Country-only addresses are skipped** — iOS fills in the country as soon as an address is started; an address with nothing more specific (no street, city, state or postal code) isn't plotted, since geocoding it lands in the middle of the country.
- **One lookup per address** — Contacts sharing an address (coworkers, family) are geocoded with a single request and all get pins from it, so a shared office doesn't spend a dozen lookups of Apple's rate limit. Progress still counts contacts.
- **Every contact with an address gets a pin** — Names come from `CNContactFormatter`, so they follow the user's Contacts display order and each name's convention (family name first for Chinese, Japanese and Korean names) and include middle names and suffixes. They fall back to company name, then nickname, then "No Name", so business and nickname-only contacts aren't silently skipped.
- **Addresses Apple Maps can't find are remembered for a day** — `MKError.placemarkNotFound` becomes `GeocodeOutcome.notFound` and a `notFound` cache entry (24h TTL). Until it expires the address is counted as unmapped without another request, so foreground retries don't spend rate-limit budget on it. Network and server failures are still never cached, and a not-found answer never replaces a known location.
- **Photo pins are drawn once per contact** — `ContactAnnotation.photoPinImage` renders lazily and is reused every time MapKit recycles the view.
- **Tests don't run the app** — The tests are hosted in the app, so `MapMyFriendsApp` shows a blank screen when `AppEnvironment.isRunningTests`; otherwise the host would request contacts and geocode real addresses during the suite.
- **Injectable controller** — `MapViewController` takes its contact store (`ContactFetching`), geocoding manager, location manager (`LocationProviding`) and debounce interval in `init`, all defaulting to the real ones, so tests drive the real controller with fakes.
- **Contact diffing** — `ContactDiffer` computes a minimal diff to add/remove only changed pins. Identity covers everything a pin displays (contact ID, address, name, label, phone), so renaming a contact or changing their number updates the pin.
- **Reuse-safe annotation views** — `ContactAnnotationView` and `ContactPhotoAnnotationView` re-apply styling in `init`, `prepareForReuse`, and `annotation didSet` to prevent red pin artifacts during cluster transitions and stop a reused photo pin from showing the previous contact's photo. Each has its own reuse identifier, chosen by `ContactAnnotation.pinReuseIdentifier`.
- **Photo pins are drawn, not glyphs** — `MKMarkerAnnotationView` renders `glyphImage` as a one-colour template, so a contact photo used as a glyph comes out as a plain white disc. `ContactPhotoAnnotationView` is a plain `MKAnnotationView` that renders the photo (aspect-filled, clipped to a circle) into its own image, with `centerOffset` putting the pointer's tip on the coordinate.
- **Feature flags via Settings.bundle** — User-facing toggles backed by `UserDefaults` for pin tap behavior and progress display.

## How It Works

1. **Launch** → `MapMyFriendsApp` registers feature flag defaults; `MapViewController` requests contacts permission and subscribes to `CNContactStoreDidChange`. Location permission is requested once the first load has finished
2. **Fetch** → `ContactsManager` enumerates all contacts with postal addresses, thumbnails, and phone numbers on a background thread
3. **Cache check** → `GeocodingManager` classifies each address in a single lookup: valid cache hit (resolve immediately), expired hit (resolve immediately at the old coordinate, then refresh), or cache miss (geocode). Legacy `failed: true` entries count as misses so they are retried
4. **Sort** → Cache hits are sorted by proximity to user location so nearby pins appear first
5. **Geocode** → Cache misses are geocoded sequentially via `MKGeocodingRequest` with 0.15s delays, backing off and retrying when throttled; expired entries are refreshed after all misses; failures are reported but never written to the cache
6. **Plot** → Each resolved contact is added to the map as a `ContactAnnotation`; clusters auto-zoom on tap
7. **Persist** → Cache saves incrementally every 10 geocodes, plus a final save on completion
8. **Report** → `onSummary` and a DEBUG log record how many contacts came from cache, were geocoded, failed, or were retried after a legacy failure
9. **Live sync** → Contact changes are deferred during the initial load, then debounced; `ContactDiffer` computes a minimal diff and only adds/removes affected pins
10. **Retry** → If any address failed to map, returning to the foreground triggers the same diff, which re-geocodes exactly the addresses that have no pin

## Tests

The project includes 275 tests using the Swift Testing framework. No test reaches Apple's geocoding service: anything that can trigger a geocode is wired to `MockGeocoder`, which answers synchronously, and the app itself stays idle while it hosts the tests, so the whole suite runs offline.

```
MapMyFriendsTests/
├── Fixtures/
│   ├── contacts-1000.json               # 1000 contacts: 50 states + DC, 65 cities worldwide
│   ├── generate_contacts_fixture.py     # Regenerates the fixture deterministically
│   └── ContactFixtures.swift            # Loader + cache/geocoder helpers
├── Mocks/
│   ├── ManualGeocoder.swift             # Async (test-controlled) and scripted geocoders
│   ├── MockCacheManager.swift           # In-memory CacheManaging with seeding helpers
│   └── MockGeocoder.swift               # Deterministic, synchronous AddressGeocoding
├── Support/
│   └── GeocodingRunner.swift            # Shared harness: run a launch, capture every callback
├── CachedCoordinateTests.swift          # Codable round-trip, JSON stability, legacy failed field
├── CacheManagerTests.swift              # Store/retrieve, TTL expiry, entry persistence
├── CacheManagerThreadSafetyTests.swift  # Concurrent read/write stress tests
├── CacheIntegrationTests.swift          # End-to-end persistence, concurrent reads
├── ContactAnnotationTests.swift         # Title, subtitle, coordinate, phone number passthrough
├── ContactDifferTests.swift             # Diff logic for live contact sync
├── ContactPlottingTests.swift           # Pipeline behaviour + use cases UC1–UC10 (30 cases)
├── ContactPlottingScaleTests.swift      # The full 1000-contact fixture end to end (16 cases)
├── GeocodingManagerTests.swift          # Cache hits, retries, proximity sort, metadata
├── AnnotationViewTests.swift            # Pin styling, reuse safety, cluster view layout
├── FeatureFlagsTests.swift              # UserDefaults-backed flag reads, overrides
├── MissingPinTests.swift                # Every known way a contact could fail to reach the map
├── PhotoPinTests.swift                  # Photo pin choice, rendering (pixel-checked), name label, reuse, live photo changes
├── PinWiringTests.swift                 # View registration and per-annotation view choice on a real MKMapView
├── ReviewFixTests.swift                 # Camera policy, cache location/migration/backup exclusion, cache pruning
├── ReviewFollowUpTests.swift            # Cluster list order, pin image caching, not-found memory, name formatting
├── MapViewControllerTests.swift         # The real controller with fake contacts/location: loads, refreshes, retries
├── AppEnvironmentTests.swift            # The app stays idle while hosting the tests
├── ReviewDecisionTests.swift            # Map-moved rule, throttle pacing, unmapped report, VoiceOver labels
├── EdgeCaseTests.swift                  # Country-only addresses, one-line callouts, shared-address lookups, phone links
└── NoDataExfiltrationTests.swift        # Verifies no sensitive data leaks
```

Run tests:
```
xcodebuild -scheme MapMyFriends -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The 1000-contact fixture exists so scale-dependent regressions are caught in CI: at that size a single mis-handled cache state silently removes hundreds of pins. Regenerate it with `python3 MapMyFriendsTests/Fixtures/generate_contacts_fixture.py` — output is byte-for-byte reproducible.

## Settings

User-configurable options are available in **iOS Settings → Map My Friends**:

- **Open Contact on Tap** — When on, tapping a pin opens the contact in the Contacts app. When off, shows Call/Message options. *(default: off)*
- **Hide Mapping Progress** — When on, suppresses the geocoding progress banner and error toast. *(default: on)*

## Roadmap

- [x] Contact change detection — live sync via `CNContactStoreDidChange` + `ContactDiffer`
- [x] Contact photo pins — circular photo pin for contacts with a photo
- [x] Error state UI — geocoding failure count toast ("3 addresses could not be mapped")
- [x] Cache TTL — 90-day expiry for successful entries; failures are not cached at all
- [x] Incremental persistence — save every 10 geocodes
- [x] Proximity sorting — nearest contacts appear first
- [x] Call/Text from pin — action sheet with Call/Message (feature-flagged)
- [x] Open in Contacts — push `CNContactViewController` from pin tap (feature-flagged)
- [x] About page — app info and GitHub link
- [x] Feature flags — Settings.bundle with user-facing toggles
- [x] Cluster zoom — tap cluster to zoom in; same-location (or fully zoomed-in) clusters show contact list
- [ ] Cache invalidation — detect when a cached address no longer matches the contact's current address
- [ ] Refresh button — nav bar button to manually re-fetch and re-geocode
- [ ] Address type color coding — different pin colors for Home vs Work vs Other

## App Store

- Bundle ID `com.Rosedale.MapMyFriends`, published by Rosedale Co
- Listing copy, review notes, and privacy answers: [`AppStore/listing.md`](AppStore/listing.md)
- Privacy policy and support pages live in [`docs/`](docs/) and are served by GitHub Pages at https://mfyameen.github.io/MapMyFriends/

## Archive

Older planning documents (original spec, implementation and test plans, security fixes) are kept in [`archive/`](archive/) for history. They are not kept up to date.

## License

Apache License 2.0. See [LICENSE](LICENSE).
