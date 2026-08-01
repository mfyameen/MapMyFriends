# MapMyFriends — Test Plan

## Overview
The project has 119 tests in the `MapMyFriendsTests` target using the Swift Testing framework (Xcode 26). Every test runs offline and synchronously — no test contacts Apple's geocoding service. UI tests are deferred since the app is single-screen and behavior is best validated manually per the testing checklist in `plan.MD`.

## Testability Architecture (implemented)
The following patterns enable isolated, deterministic testing:

- `CacheManager`: Conforms to the `CacheManaging` protocol and accepts `init(fileURL:ttl:failedTtl:)` so tests use isolated temp files and short TTLs instead of the real documents directory. The `shared` singleton is used in production.
- `GeocodingManager`: Accepts `CacheManaging`, `AddressGeocoding`, and `requestDelay` via init (all defaulted for production). Tests inject `MockCacheManager` + `MockGeocoder` with `requestDelay: 0`.
- `AddressGeocoding`: Protocol seam over MapKit geocoding. `MapKitGeocoder` wraps `MKGeocodingRequest` in production; `MockGeocoder` returns scripted `GeocodeOutcome` values (success / invalidAddress / failed) synchronously in tests. Without this seam every cache miss would hit the live network.
- `ContactChangeCoalescer`: The `CNContactStoreDidChange` initial-load gate, extracted from `MapViewController` so it can be unit tested without UIKit. The 1-second debounce timer itself stays in the controller and is covered by the manual checklist.
- `GeocodingRunner` (`Support/`): Shared harness that runs one `process()` call and captures resolved contacts, progress events, the summary, and the completion count.
- `ContactFixtures` (`Fixtures/`): Loads `contacts-1000.json` from disk via `#filePath` and builds pre-seeded caches and geocoders from it.
- `ContactsManager`: No mock needed — contact fetching requires a real `CNContactStore` and is impractical to unit test.
- `MapViewController`: No mock needed — it's a coordinator best covered by the manual testing checklist.

## Unit Tests

### 1. CachedCoordinate Tests (`CachedCoordinateTests.swift`)
Pure value type — no mocking needed.
- **Codable round-trip**: Encode a `CachedCoordinate` to JSON, decode it back, verify lat/lng/cachedAt match
- **JSON stability**: Decode from a known JSON string to verify the schema doesn't drift
- **Date precision**: Verify `cachedAt` survives encoding without losing meaningful precision
- **Failed defaults to false**: Default init has `failed == false`
- **Failed true round-trip**: `failed: true` survives encode/decode
- **Backward compat**: JSON without `failed` key decodes as `false`

### 2. CacheManager Tests (`CacheManagerTests.swift`)
Each test uses an isolated temp file via `init(fileURL:)`.
- **Store and retrieve**: Store a coordinate for an address, retrieve it, verify match
- **Cache miss returns nil**: Query an address that was never stored
- **Overwrite**: Store twice for the same address, verify latest value wins
- **Save and reload round-trip**: Store entries, call `saveToDisk()`, create a new `CacheManager` from the same file, verify entries persist
- **Empty file on first load**: Init with a non-existent file path — should start with empty cache, no crash
- **Corrupt file recovery**: Write garbage data to the file, init CacheManager — should recover with empty cache
- **Multiple entries**: Store 100 entries, save, reload, verify all present
- **Fresh entry within TTL**: Entry within TTL is returned
- **Stale entry returns nil**: Entry past TTL returns nil
- **Zero TTL rejects everything**: Edge case for zero TTL
- **Failed entry persists and reloads**: Failed entry survives save/reload cycle

### 3. CacheManager Thread Safety Tests (`CacheManagerThreadSafetyTests.swift`)
Stress tests for the `DispatchQueue`-based thread safety in `CacheManager`.
- **Concurrent read/write**: Hammer `store` and `coordinate(for:)` from multiple threads simultaneously, verify no crashes or data corruption

### 4. ContactAnnotation Tests (`ContactAnnotationTests.swift`)
Pure logic — no mocking needed.
- **Title**: Verify `title` returns `fullName` from the `MappedContact`
- **Subtitle format**: Verify subtitle is `"label · address"`
- **Coordinate passthrough**: Verify `coordinate` matches the `MappedContact`'s coordinate
- **Phone number nil by default**: Verify nil phone number
- **Phone number stored**: Verify phone number passthrough
- **Phone number empty string**: Verify empty string is preserved

### 5. ContactDiffer Tests (`ContactDifferTests.swift`)
Pure function — no mocking needed.
- Tests the `ContactDiffer.diff()` function with various scenarios: no changes, additions, removals, and mixed add/remove cases
- Verifies correct `toRemoveIndices` and `toAdd` arrays using `(contactID, addressString)` as identity key

### 6. GeocodingManager Tests (`GeocodingManagerTests.swift`)
Uses `MockCacheManager` to isolate from disk I/O, and `MockGeocoder` to isolate from the network.
- **All cache hits — no geocoding**: Process addresses that are all cached, verify `onContactResolved` called for each, `onComplete` called, no network requests
- **All cache hits — onComplete fires**: Verify `onComplete` is called even when there are zero misses
- **Empty input**: Process an empty array, verify `onComplete` fires immediately
- **Cache hit coordinates correct**: Verify resolved coordinates match cached values
- **Cancel triggers save**: Verify `saveToDisk()` is called on cancel
- **All cache hits do not trigger save**: No save when all entries are cache hits
- **Metadata preservation**: Verify contactID, fullName, addressLabel, addressString passthrough
- **Phone number preserved**: Verify phone number passes through from raw address to resolved contact
- **Nil phone number preserved**: Verify nil phone number is not lost
- **Legacy failed entry retried**: A `failed: true` entry is re-geocoded rather than skipped, and resolves when the retry succeeds
- **Repeat failure reported**: A retry that fails again is counted in `onComplete`, and no new failure entry is written to the cache
- **Mix of success and legacy failed**: The cache hit resolves and the legacy failure resolves after retry
- **onComplete reports zero for all hits**: Failure count is 0 when all are cache hits
- **Proximity sort orders nearest first**: With user location, nearest contact resolves first
- **No user location preserves order**: Without user location, original order is kept

### 7. Annotation View Tests (`AnnotationViewTests.swift`)
Combined view configuration tests for both `ContactAnnotationView` and `ClusterAnnotationView`.
- **Clustering identifier**: Verify `clusteringIdentifier == "contact"`
- **Marker tint color**: Verify `markerTintColor == .systemBlue`
- **Glyph image**: Verify `glyphImage` is set (non-nil)
- **No avatar keeps default glyph**: Nil thumbnail keeps person icon and blue tint
- **Valid avatar switches to gray**: Valid image data changes tint to systemGray
- **Invalid avatar falls back**: Bad data reverts to default styling
- **Right callout accessory**: Verify `rightCalloutAccessoryView` is a detail disclosure button
- **prepareForReuse resets to blue**: Corrupted styling recovers on reuse
- **annotation didSet resets style**: Style reapplied when annotation property changes
- **Cluster frame size**: Verify frame is 40×40
- **Circle background color**: Verify `.systemBlue` background
- **Corner radius**: Verify corner radius 20 (fully round)

### 8. NoDataExfiltration Tests (`NoDataExfiltrationTests.swift`)
Security/privacy smoke tests.
- Verifies no sensitive contact data is leaked via logs, analytics, or unintended persistence paths

### 9. FeatureFlags Tests (`FeatureFlagsTests.swift`)
Tests for the UserDefaults-backed feature flag system.
- **Register defaults sets expected values**: Fresh UserDefaults suite returns registered values
- **User override wins**: Explicit set overrides registered default
- **Flags read from standard defaults**: FeatureFlags reads from UserDefaults.standard
- **Setting standard defaults affects flags**: Writing UserDefaults changes flag values

### 10. Contact Plotting Tests (`ContactPlottingTests.swift`)
End-to-end tests for the full plotting pipeline, including the ten use cases from the contact-plotting bug investigation (30 test cases).
- **Basic cache hit resolution**: Single and multiple cached addresses resolve to pins
- **Cache miss handling**: Uncached addresses are geocoded and the result is cached
- **Legacy failed entries**: Treated as cache misses and retried; a `0,0` failure entry is never plotted as a pin
- **Failures are never cached**: Neither geocode failures nor invalid address strings are written to the cache
- **TTL expiry**: Stale successes are re-geocoded; expired entries return nil from the cache
- **Metadata passthrough**: All fields (contactID, name, label, address, thumbnail, phone, coordinates) survive both the cache path and the geocode path
- **Proximity sorting**: SF/NYC/Paris ordered by distance to user location
- **Process stability**: Double-call doesn't duplicate; counters reset per run; empty input completes immediately; cancel stops the in-flight request and persists
- **Cache persistence integration**: Successful entries survive save/reload; persisted legacy failures are retried after reload
- **UC1–UC10**: Cold start, warm start, warm start with new contacts, transient failure recovery, permission-grant deferral, contact deletion, invalid address retry, a cache full of legacy failures, mixed cache state, and a notification storm

### 11. Contact Plotting Scale Tests (`ContactPlottingScaleTests.swift`)
Drives the full 1000-contact fixture through the pipeline (16 test cases). These exist because the original regression was scale-dependent: at 1000 contacts a single mishandled cache state silently removes hundreds of pins.
- **Fixture integrity**: 1000 unique IDs, addresses, and coordinates; multi-line addresses; valid lat/lng ranges
- **Global coverage**: All 50 states plus DC, 40+ countries, and latitude/longitude spread across the inhabited continents
- **Cold start**: All 1000 geocoded, plotted, and cached; every coordinate survives the pipeline unchanged
- **Progress reporting**: One event per geocoded address with a consistent total
- **Warm start**: All 1000 resolve from cache with zero geocodes and no progress banner
- **Warm start with new contacts**: 950 cached + 50 new — only the new ones are geocoded
- **Transient failure recovery**: 143 failures plot nothing this launch, are not cached, and all resolve on the next launch
- **Cache full of legacy failures**: All 1000 retried and recovered — the reported bug, reproduced at full scale
- **Total outage**: 500 failures leave the cache untouched and every contact retries afterwards
- **Invalid addresses**: 40 unparseable strings are counted, uncached, and retried
- **Mixed cache state**: 700 hits + 150 legacy failures + 150 misses = 1000 pins, nothing lost or duplicated
- **Global proximity ordering**: All 1000 pins arrive nearest-first by real distance from San Francisco
- **Diffing at scale**: 100 deletions and 100 additions computed correctly
- **Persistence at scale**: 1000 entries survive a disk round trip

## Integration Tests

### 12. Cache Persistence Integration (`CacheIntegrationTests.swift`)
End-to-end test using a real temp file (no mocks).
- **Write → kill → read**: Create a CacheManager with a temp file, store entries, save, deallocate, create a new instance from the same file, verify all entries are present
- **Concurrent reads**: Store entries, save, read from multiple threads — verify no crashes (smoke test)

## Test Fixture
`Fixtures/contacts-1000.json` holds 1000 contacts with unique addresses and coordinates, covering all 50 US states plus DC and 65 cities across 6 continents. US and international addresses use different multi-line formats, mirroring `CNPostalAddressFormatter` output. Coordinates are real city centres with a small deterministic offset so no two contacts share a pin.

The file is read straight off disk through `#filePath` rather than the test bundle, so it does not depend on resource copying. `generate_contacts_fixture.py` sits beside it and regenerates the JSON byte-for-byte:
```
python3 MapMyFriendsTests/Fixtures/generate_contacts_fixture.py
```

## What's NOT Tested (and why)
- **ContactsManager**: Requires a real `CNContactStore` with contacts permission. Impractical in CI.
- **MapViewController**: UIKit lifecycle coordination. Best covered by the manual testing checklist in `plan.MD`. The initial-load gate it delegates to (`ContactChangeCoalescer`) *is* unit tested; the 1-second debounce timer is not.
- **MKGeocodingRequest networking**: We don't test Apple's geocoding service. `MapKitGeocoder` is the thin, untested adapter around it; everything above the `AddressGeocoding` seam is fully covered.

## Known Failing Tests (pre-existing, out of scope)
- `NoDataExfiltrationTests/noForbiddenNetworkPatterns` — the scanner flags the legitimate GitHub link at `MapMyFriends/Views/AboutView.swift:109`. Needs a policy decision: allowlist the line or move the URL out of source.
- `ContactAnnotationViewTests/validAvatarSwitchesMarkerToGray` — relates to the disabled contact-avatar feature.

## File Structure
```
MapMyFriendsTests/
├── Fixtures/
│   ├── contacts-1000.json
│   ├── generate_contacts_fixture.py
│   └── ContactFixtures.swift
├── Mocks/
│   ├── MockCacheManager.swift
│   └── MockGeocoder.swift
├── Support/
│   └── GeocodingRunner.swift
├── CachedCoordinateTests.swift
├── CacheManagerTests.swift
├── CacheManagerThreadSafetyTests.swift
├── CacheIntegrationTests.swift
├── ContactAnnotationTests.swift
├── ContactDifferTests.swift
├── ContactPlottingTests.swift
├── ContactPlottingScaleTests.swift
├── GeocodingManagerTests.swift
├── AnnotationViewTests.swift
├── FeatureFlagsTests.swift
└── NoDataExfiltrationTests.swift
```
