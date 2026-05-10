# MapMyFriends — Test Plan

## Overview
The app currently has no test targets. This plan covers unit tests, integration tests, and a testability refactor needed to make the managers mockable. UI tests are deferred since the app is single-screen and behavior is best validated manually per the existing testing checklist in `plan.MD`.

## Testability Refactor (prerequisite)
The current code uses singletons and concrete types directly, making unit testing difficult. Before writing tests, we need to introduce protocols for dependency injection.

**Changes needed in main target:**
- `CacheManager`: Extract a `CacheManaging` protocol and add an `init(fileURL:)` initializer so tests can use a temp directory instead of the real documents folder. Keep the `shared` singleton for production use.
- `GeocodingManager`: Accept a `CacheManaging` dependency via init instead of referencing `CacheManager.shared` directly. This lets tests inject a mock cache.
- `ContactsManager`: No refactor needed — contact fetching requires a real `CNContactStore` and is impractical to unit test.
- `MapViewController`: No refactor needed for now — it's a coordinator and is best covered by UI tests.

## Test Target Setup
Add an Xcode unit test target: `MapMyFriendsTests` (Swift Testing framework, since we're on Xcode 26).

## Unit Tests

### 1. CachedCoordinate Tests (`CachedCoordinateTests.swift`)
Pure value type — no mocking needed.
- **Codable round-trip**: Encode a `CachedCoordinate` to JSON, decode it back, verify lat/lng/cachedAt match
- **JSON stability**: Decode from a known JSON string to verify the schema doesn't drift
- **Date precision**: Verify `cachedAt` survives encoding without losing meaningful precision

### 2. CacheManager Tests (`CacheManagerTests.swift`)
Requires the `init(fileURL:)` refactor so each test uses an isolated temp file.
- **Store and retrieve**: Store a coordinate for an address, retrieve it, verify match
- **Cache miss returns nil**: Query an address that was never stored
- **Overwrite**: Store twice for the same address, verify latest value wins
- **Save and reload round-trip**: Store entries, call `saveToDisk()`, create a new `CacheManager` from the same file, verify entries persist
- **Empty file on first load**: Init with a non-existent file path — should start with empty cache, no crash
- **Corrupt file recovery**: Write garbage data to the file, init CacheManager — should recover with empty cache
- **Multiple entries**: Store 100 entries, save, reload, verify all present

### 3. ContactAnnotation Tests (`ContactAnnotationTests.swift`)
Pure logic — no mocking needed.
- **Title**: Verify `title` returns `fullName` from the `MappedContact`
- **Subtitle format**: Verify subtitle is `"label · address"`
- **Coordinate passthrough**: Verify `coordinate` matches the `MappedContact`'s coordinate

### 4. GeocodingManager Tests (`GeocodingManagerTests.swift`)
Requires mock `CacheManaging` to isolate from disk I/O and network.
- **All cache hits — no geocoding**: Process addresses that are all cached, verify `onContactResolved` called for each, `onComplete` called, no network requests
- **All cache hits — onComplete fires**: Verify `onComplete` is called even when there are zero misses
- **Empty input**: Process an empty array, verify `onComplete` fires immediately
- **Progress callback count**: Process N cache misses, verify `onProgress` is called N times with correct (completed, total) values
- **Cache store on geocode success**: After a successful geocode, verify the result is stored in the mock cache
- **Batch save on complete**: Verify `saveToDisk()` is called once when all misses are processed (not per-entry)
- **Cancel stops processing**: Start processing, call `cancel()` after first geocode, verify remaining addresses are not processed
- **Cancel triggers save**: Verify `saveToDisk()` is called on cancel
- **Invalid address string skipped**: If `MKGeocodingRequest(addressString:)` returns nil, verify it's skipped and progress still advances

### 5. ContactAnnotationView Tests (`ContactAnnotationViewTests.swift`)
View configuration tests.
- **Clustering identifier**: Verify `clusteringIdentifier == "contact"`
- **Marker tint color**: Verify `markerTintColor == .systemBlue`
- **Callout enabled**: Verify `canShowCallout == true`
- **Glyph image**: Verify `glyphImage` is set (non-nil)

### 6. ClusterAnnotationView Tests (`ClusterAnnotationViewTests.swift`)
View configuration tests.
- **Frame size**: Verify frame is 40×40
- **Circle background color**: Verify the circle view has `.systemBlue` background
- **Corner radius**: Verify the circle has corner radius 20 (fully round)

## Integration Tests

### 7. Cache Persistence Integration (`CacheIntegrationTests.swift`)
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
├── ContactAnnotationTests.swift
├── GeocodingManagerTests.swift
├── ContactAnnotationViewTests.swift
├── ClusterAnnotationViewTests.swift
└── CacheIntegrationTests.swift
```
