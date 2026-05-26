# MapMyFriends — Test Plan

## Overview
The project has 48 tests in the `MapMyFriendsTests` target using the Swift Testing framework (Xcode 26). UI tests are deferred since the app is single-screen and behavior is best validated manually per the testing checklist in `plan.MD`.

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

### 2. CacheManager Tests (`CacheManagerTests.swift`)
Each test uses an isolated temp file via `init(fileURL:)`.
- **Store and retrieve**: Store a coordinate for an address, retrieve it, verify match
- **Cache miss returns nil**: Query an address that was never stored
- **Overwrite**: Store twice for the same address, verify latest value wins
- **Save and reload round-trip**: Store entries, call `saveToDisk()`, create a new `CacheManager` from the same file, verify entries persist
- **Empty file on first load**: Init with a non-existent file path — should start with empty cache, no crash
- **Corrupt file recovery**: Write garbage data to the file, init CacheManager — should recover with empty cache
- **Multiple entries**: Store 100 entries, save, reload, verify all present

### 3. CacheManager Thread Safety Tests (`CacheManagerThreadSafetyTests.swift`)
Stress tests for the `DispatchQueue`-based thread safety in `CacheManager`.
- **Concurrent read/write**: Hammer `store` and `coordinate(for:)` from multiple threads simultaneously, verify no crashes or data corruption

### 4. ContactAnnotation Tests (`ContactAnnotationTests.swift`)
Pure logic — no mocking needed.
- **Title**: Verify `title` returns `fullName` from the `MappedContact`
- **Subtitle format**: Verify subtitle is `"label · address"`
- **Coordinate passthrough**: Verify `coordinate` matches the `MappedContact`'s coordinate

### 5. ContactDiffer Tests (`ContactDifferTests.swift`)
Pure function — no mocking needed.
- Tests the `ContactDiffer.diff()` function with various scenarios: no changes, additions, removals, and mixed add/remove cases
- Verifies correct `toRemoveIndices` and `toAdd` arrays using `(contactID, addressString)` as identity key

### 6. GeocodingManager Tests (`GeocodingManagerTests.swift`)
Uses `MockCacheManager` to isolate from disk I/O and network.
- **All cache hits — no geocoding**: Process addresses that are all cached, verify `onContactResolved` called for each, `onComplete` called, no network requests
- **All cache hits — onComplete fires**: Verify `onComplete` is called even when there are zero misses
- **Empty input**: Process an empty array, verify `onComplete` fires immediately
- **Progress callback count**: Process N cache misses, verify `onProgress` is called N times with correct (completed, total) values
- **Cache store on geocode success**: After a successful geocode, verify the result is stored in the mock cache
- **Batch save on complete**: Verify `saveToDisk()` is called once when all misses are processed (not per-entry)
- **Cancel stops processing**: Start processing, call `cancel()` after first geocode, verify remaining addresses are not processed
- **Cancel triggers save**: Verify `saveToDisk()` is called on cancel
- **Invalid address string skipped**: If `MKGeocodingRequest(addressString:)` returns nil, verify it's skipped and progress still advances
- **Metadata preservation**: Verify `thumbnailImageData` is passed through from `RawContactAddress` to `MappedContact`

### 7. Annotation View Tests (`AnnotationViewTests.swift`)
Combined view configuration tests for both `ContactAnnotationView` and `ClusterAnnotationView`.
- **Clustering identifier**: Verify `clusteringIdentifier == "contact"`
- **Marker tint color**: Verify `markerTintColor == .systemBlue`
- **Callout enabled**: Verify `canShowCallout == true`
- **Glyph image**: Verify `glyphImage` is set (non-nil)
- **Cluster frame size**: Verify frame is 40×40
- **Circle background color**: Verify the circle view has `.systemBlue` background
- **Corner radius**: Verify the circle has corner radius 20 (fully round)

### 8. NoDataExfiltration Tests (`NoDataExfiltrationTests.swift`)
Security/privacy smoke tests.
- Verifies no sensitive contact data is leaked via logs, analytics, or unintended persistence paths

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
├── GeocodingManagerTests.swift
├── AnnotationViewTests.swift
└── NoDataExfiltrationTests.swift
```
