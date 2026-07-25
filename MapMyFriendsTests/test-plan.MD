# MapMyFriends — Test Plan

## Overview
The project has 91 tests in the `MapMyFriendsTests` target using the Swift Testing framework (Xcode 26). UI tests are deferred since the app is single-screen and behavior is best validated manually per the testing checklist in `plan.MD`.

## Testability Architecture (implemented)
The following patterns enable isolated, deterministic testing:

- `CacheManager`: Conforms to the `CacheManaging` protocol and accepts `init(fileURL:)` so tests use isolated temp files instead of the real documents directory. The `shared` singleton is used in production.
- `GeocodingManager`: Accepts a `CacheManaging` dependency via init (defaults to `CacheManager.shared`), enabling mock injection in tests via `MockCacheManager`.
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
Uses `MockCacheManager` to isolate from disk I/O and network.
- **All cache hits — no geocoding**: Process addresses that are all cached, verify `onContactResolved` called for each, `onComplete` called, no network requests
- **All cache hits — onComplete fires**: Verify `onComplete` is called even when there are zero misses
- **Empty input**: Process an empty array, verify `onComplete` fires immediately
- **Cache hit coordinates correct**: Verify resolved coordinates match cached values
- **Cancel triggers save**: Verify `saveToDisk()` is called on cancel
- **All cache hits do not trigger save**: No save when all entries are cache hits
- **Metadata preservation**: Verify contactID, fullName, addressLabel, addressString passthrough
- **Phone number preserved**: Verify phone number passes through from raw address to resolved contact
- **Nil phone number preserved**: Verify nil phone number is not lost
- **Failed cache entry skipped**: Failed entries don't resolve and don't trigger geocoding
- **Mix of success and failed**: Only non-failed entries resolve
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
Comprehensive end-to-end tests for the full plotting pipeline (22 test cases).
- **Basic cache hit resolution**: Single and multiple cached addresses resolve to pins
- **Cache miss handling**: Uncached addresses don't resolve from cache
- **Failed entry behavior**: Failed entries skip silently, don't retry, not confused with successes
- **TTL expiry**: Stale successes become misses; stale failures trigger retry; separate TTLs validated
- **Mixed scenarios**: Hits + failed + misses together; contacts with multiple addresses
- **Metadata passthrough**: All fields (contactID, name, label, address, thumbnail, phone, coordinates) survive the pipeline
- **Proximity sorting**: SF/NYC/Paris ordered by distance to user location
- **Process stability**: Double-call doesn't duplicate; empty input completes immediately
- **Cache persistence integration**: Entries survive save/reload for both success and failure
- **Dual TTL validation**: 30s-old success valid with long TTL; 30s-old failure expired with short TTL

## Integration Tests

### 9. Cache Persistence Integration (`CacheIntegrationTests.swift`)
End-to-end test using a real temp file (no mocks).
- **Write → kill → read**: Create a CacheManager with a temp file, store entries, save, deallocate, create a new instance from the same file, verify all entries are present
- **Concurrent reads**: Store entries, save, read from multiple threads — verify no crashes (smoke test)

## What's NOT Tested (and why)
- **ContactsManager**: Requires a real `CNContactStore` with contacts permission. Impractical in CI.
- **MapViewController**: UIKit lifecycle coordination. Best covered by the manual testing checklist in `plan.MD`.
- **MKGeocodingRequest networking**: We don't test Apple's geocoding service. The GeocodingManager tests verify orchestration logic only.

## File Structure
```
MapMyFriendsTests/
├── Mocks/
│   └── MockCacheManager.swift
├── CachedCoordinateTests.swift
├── CacheManagerTests.swift
├── CacheManagerThreadSafetyTests.swift
├── CacheIntegrationTests.swift
├── ContactAnnotationTests.swift
├── ContactDifferTests.swift
├── ContactPlottingTests.swift
├── GeocodingManagerTests.swift
├── AnnotationViewTests.swift
├── FeatureFlagsTests.swift
└── NoDataExfiltrationTests.swift
```
