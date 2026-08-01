Here's a thorough engineering spec you can hand directly to Claude Code or Warp:

---

# Map My Friends — Engineering Spec

## Project Overview

An iOS app (UIKit) that reads a user's phone contacts, geocodes their addresses, and plots them as clustered pins on a full-screen map. The user's own location is shown as a blue dot. Tapping a pin shows the contact's name and address type. All geocoding results are cached locally so subsequent launches are near-instant.

**Target: iOS 26+, Swift 5.9, SwiftUI lifecycle + UIKit map, no third-party dependencies.**

---

## Xcode Project Setup

- Create a new Xcode project: App template, Swift, SwiftUI lifecycle
- Product name: `MapMyFriends`
- Bundle ID: `com.yourname.MapMyFriends`
- No storyboard — the SwiftUI `@main` app entry point (`MapMyFriendsApp.swift`) hosts the UIKit map via `UIViewControllerRepresentable`
- Minimum deployment target: iOS 26.0

**Info.plist — add these keys:**
```xml
<key>NSContactsUsageDescription</key>
<string>Map My Friends needs access to your contacts to plot their addresses on the map.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Map My Friends shows your current location on the map.</string>
```

---

## File Structure

```
MapMyFriends/
├── MapMyFriendsApp.swift             # SwiftUI @main entry point
├── FeatureFlags.swift                # UserDefaults-backed flags (Settings.bundle)
├── Controllers/
│   └── MapViewController.swift       # Root UIKit VC — map, location, orchestration
├── Managers/
│   ├── AddressGeocoding.swift        # AddressGeocoding protocol + MapKitGeocoder
│   ├── CacheManager.swift            # JSON cache with CacheManaging protocol & thread-safe queue
│   ├── ContactChangeCoalescer.swift  # Initial-load gate for CNContactStoreDidChange
│   ├── ContactsManager.swift         # Contacts permission & fetch (incl. thumbnails)
│   ├── ContactDiffer.swift           # Pure-function diff for live contact sync
│   └── GeocodingManager.swift        # Sequential geocoding via the AddressGeocoding seam
├── Models/
│   ├── MappedContact.swift           # Contact + coordinate + optional thumbnail
│   └── CachedCoordinate.swift        # Codable lat/lng/timestamp
├── Views/
│   ├── AboutView.swift               # SwiftUI About page
│   ├── ContactAnnotation.swift       # MKAnnotation wrapper
│   ├── ContactAnnotationView.swift   # Person pin with avatar support & clustering
│   ├── ClusterAnnotationView.swift   # Circle with count badge
│   └── MapViewControllerWrapper.swift # UIViewControllerRepresentable bridge
├── Settings.bundle/
└── Assets.xcassets/
```

---

## Models

### `MappedContact.swift`
```swift
import CoreLocation

struct MappedContact: Sendable {
    let contactID: String        // CNContact.identifier
    let fullName: String
    let addressLabel: String     // "Home", "Work", "Other", etc.
    let addressString: String    // raw formatted address, used as cache key
    let coordinate: CLLocationCoordinate2D
    let thumbnailImageData: Data?  // contact avatar (currently disabled)
    let phoneNumber: String?       // preferred phone number for Call/Message
}
```

### `CachedCoordinate.swift`
```swift
import Foundation

struct CachedCoordinate: Codable, Sendable {
    let lat: Double
    let lng: Double
    let cachedAt: Date
    let failed: Bool    // legacy: no longer written. Older builds cached failures here;
                        // such entries are now treated as cache misses and retried.
}
```

---

## CacheManager

**File:** `Managers/CacheManager.swift`

**Responsibilities:** Read and write a JSON file that maps raw address strings to `CachedCoordinate` values. This is the sole persistence layer.

**Cache file location:** `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first` + `address_cache.json`

**Public interface:**
```swift
protocol CacheManaging {
    func coordinate(for address: String) -> CachedCoordinate?
    func store(coordinate: CachedCoordinate, for address: String)
    func saveToDisk()
}

class CacheManager: CacheManaging {
    nonisolated(unsafe) static let shared = CacheManager()

    private var cache: [String: CachedCoordinate] = [:]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.mapmyfriends.cachemanager")

    private convenience init()   // production singleton — documents directory
    init(fileURL: URL)           // testable init — custom file URL

    func coordinate(for address: String) -> CachedCoordinate?
    func store(coordinate: CachedCoordinate, for address: String)
    func saveToDisk()
}
```

**Implementation notes:**
- All reads/writes to the `cache` dictionary are synchronized via a serial `DispatchQueue` for thread safety.
- Load the JSON file in `init(fileURL:)` using `JSONDecoder`. If the file doesn't exist yet, start with an empty dictionary.
- `store(coordinate:for:)` updates the in-memory dictionary (thread-safe). Disk writes are batched — `saveToDisk()` is called once after all geocoding completes (or on cancel), not per-entry.
- `saveToDisk()` encodes the full dictionary with `JSONEncoder` and writes to the file path using `Data.write(to:options:[.atomic, .completeFileProtection])`. Atomic write prevents corruption if the app is killed mid-write.
- The `CacheManaging` protocol enables dependency injection for testing via `MockCacheManager`.
- The cache dictionary key is the raw address string exactly as it comes from `CNPostalAddressFormatter`. No normalization needed — consistency of the key is what matters.
- **TTL**: Successful entries expire after 90 days (`cacheTTL`). `failedTTL` (24 hours) now only bounds legacy `failed: true` entries left on disk by older builds — nothing writes failures any more. Both TTLs are injectable via `init(fileURL:ttl:failedTtl:)` for testing.
- `coordinate(for:)` checks the entry's age against the appropriate TTL and returns `nil` for stale entries. Deciding what to do with a `failed` entry is `GeocodingManager`'s job, not the cache's.

---

## ContactsManager

**File:** `Managers/ContactsManager.swift`

**Responsibilities:** Request Contacts permission, fetch all contacts that have at least one postal address, and return them as an array of raw data ready for geocoding.

**Public interface:**
```swift
class ContactsManager {

    struct RawContactAddress: Sendable {
        let contactID: String
        let fullName: String
        let addressLabel: String    // human-readable label
        let addressString: String   // formatted for geocoding
        let thumbnailImageData: Data?  // contact avatar
        let phoneNumber: String?       // preferred phone (mobile > first)
    }

    func requestAccessAndFetch(completion: @escaping @Sendable ([RawContactAddress]) -> Void)
}
```

**Implementation notes:**
- Use `CNContactStore().requestAccess(for: .contacts)` to prompt the user.
- If access is denied, call `completion([])` and surface an alert in `MapViewController` (see below).
- Fetch using `CNContactFetchRequest` with these keys to request: `[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPostalAddressesKey, CNContactIdentifierKey, CNContactThumbnailImageDataKey, CNContactPhoneNumbersKey]`
- For phone numbers, prefer mobile/iPhone label, then fall back to the first available number.
- Use `CNPostalAddressFormatter.string(from:style:.mailingAddress)` to convert each `CNPostalAddress` to a geocodable string.
- For the address label, use `CNLabeledValue<CNPostalAddress>.label` and run it through `CNLabeledValue<CNPostalAddress>.localizedString(forLabel:)` to get "Home", "Work", etc. If the label is nil or empty, fall back to "Other".
- Return one `RawContactAddress` per address — so a contact with two addresses yields two entries.
- Perform the fetch on a background thread (`DispatchQueue.global(qos: .userInitiated)`), then call `completion` on the main thread.

---

## GeocodingManager

**File:** `Managers/GeocodingManager.swift`

**Responsibilities:** Accept a list of `RawContactAddress` items, check the cache for each, geocode any cache misses sequentially, and report results back progressively.

**Public interface:**
```swift
@MainActor
class GeocodingManager {

    /// Breakdown of a single `process()` run.
    struct Summary: Equatable {
        var resolvedFromCache = 0
        var geocoded = 0
        var failed = 0                 // includes invalidAddressStrings
        var invalidAddressStrings = 0
        var retriedCachedFailures = 0  // legacy `failed: true` entries retried
        var attempted: Int { resolvedFromCache + geocoded + failed }
    }

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Parameter is the number of addresses that failed to geocode.
    var onComplete: ((Int) -> Void)?
    /// Fires immediately before `onComplete` with the full breakdown.
    var onSummary: ((Summary) -> Void)?

    private let cache: CacheManaging
    private let geocoder: AddressGeocoding
    private let requestDelay: TimeInterval

    init(cache: CacheManaging? = nil,
         geocoder: AddressGeocoding? = nil,
         requestDelay: TimeInterval = 0.15)
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil)
    func cancel()
}
```

**Implementation notes:**
- The class is `@MainActor`-isolated. `CacheManaging`, `AddressGeocoding`, and `requestDelay` are all injectable for testability; defaults are constructed **inside the init body**, since default argument expressions are evaluated in a nonisolated context and cannot touch main-actor state.
- On `process(addresses:userLocation:)`, classify each address in a **single cache lookup**: valid cache hit (resolve immediately) or cache miss (geocode). This single-lookup approach eliminates a previous double-lookup race condition.
- A legacy `failed: true` entry counts as a **cache miss** and is retried, incrementing `retriedCachedFailures`. It is never resolved to a pin (its coordinate is `0,0`) and never silently skipped — skipping it was what hid contacts for 24 hours at a time.
- If `userLocation` is provided, resolved cache hits are sorted by proximity so nearby pins appear first.
- For cache misses: geocode sequentially through `AddressGeocoding`. Do NOT geocode in parallel — Apple rate-limits geocoding aggressively.
- **Never cache a failure.** Neither a failed geocode nor an unparseable address string is written to the cache, so both are retried on the next launch. Failures are counted and reported instead.
- Between each geocode call, add a `requestDelay` (0.15s in production) via `DispatchQueue.main.asyncAfter`.
- The sequential walk is a **loop, not per-address recursion**: a geocoder that calls back synchronously (as the test mock does) advances the loop, so 1000 addresses don't build a 1000-frame stack. An asynchronous callback schedules the next step instead.
- **Incremental persistence**: `cache.saveToDisk()` is called every 10 geocodes, plus on completion and on cancel.
- `onComplete(failedCount)` reports the number of addresses that failed to geocode; `onSummary` reports the full breakdown, which is also logged in DEBUG regardless of the `hideGeocodingToasts` flag.
- All callbacks are delivered on the main thread (guaranteed by `@MainActor` isolation).

---

## AddressGeocoding

**File:** `Managers/AddressGeocoding.swift`

**Responsibilities:** Isolate MapKit geocoding behind a protocol so the pipeline can be tested offline.

```swift
enum GeocodeOutcome {
    case success(CLLocationCoordinate2D)
    case invalidAddress          // request couldn't be built — free to retry, never cache
    case failed(reason: String?) // attempted but no usable result
}

@MainActor
protocol AddressGeocoding {
    func geocode(_ address: String, completion: @escaping (GeocodeOutcome) -> Void)
    func cancelInFlight()
}
```

- `MapKitGeocoder` is the production implementation, wrapping `MKGeocodingRequest(addressString:)` and `.getMapItems()`.
- `invalidAddress` is distinguished from `failed` because building the request costs nothing — it can fail for valid addresses due to formatting or encoding quirks, so it must never be treated as a durable failure.

---

## ContactChangeCoalescer

**File:** `Managers/ContactChangeCoalescer.swift`

**Responsibilities:** Decide what an incoming `CNContactStoreDidChange` notification should do.

Granting contacts permission fires the notification while the *initial* geocoding pass is still running. Acting on it cancels that pass and drops every contact not yet geocoded. The coalescer defers changes that arrive during the initial load and collapses them into a single refresh afterwards.

```swift
final class ContactChangeCoalescer {
    enum Decision { case deferUntilInitialLoadCompletes, scheduleRefresh }

    func noteChange() -> Decision
    func noteInitialLoadComplete() -> Bool   // true if a deferred refresh is now due
}
```

The 1-second debounce window that coalesces rapid bursts lives in `MapViewController`, which owns the `DispatchWorkItem`.

---

## ContactAnnotation

**File:** `Views/ContactAnnotation.swift`

```swift
import MapKit

class ContactAnnotation: NSObject, MKAnnotation {
    let mappedContact: MappedContact
    var coordinate: CLLocationCoordinate2D { mappedContact.coordinate }
    var title: String? { mappedContact.fullName }
    var subtitle: String? { "\(mappedContact.addressLabel) · \(mappedContact.addressString)" }

    init(mappedContact: MappedContact) {
        self.mappedContact = mappedContact
    }
}
```

---

## ContactAnnotationView

**File:** `Views/ContactAnnotationView.swift`

**Responsibilities:** The visual pin shown on the map for each contact.

**Implementation notes:**
- Subclass `MKMarkerAnnotationView`
- All styling is centralized in `applyDefaultStyle()`, called from `init`, `prepareForReuse()`, and `annotation didSet` to prevent red pin artifacts during MapKit's cluster transitions.
- `clusteringIdentifier = "contact"` enables MapKit's native clustering
- `markerTintColor`: `.systemBlue`
- `glyphImage`: person SF Symbol (`UIImage(systemName: "person.fill")`)
- `canShowCallout = true` with `rightCalloutAccessoryView = UIButton(type: .detailDisclosure)`
- Contact avatar display is currently disabled (TODO: fix rendering issues)
- The delegate explicitly dequeues views in `mapView(_:viewFor:)` instead of returning `nil`, and single-member clusters are displayed as regular pins
- Register via `mapView.register(ContactAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)`

---

## ClusterAnnotationView

**File:** `Views/ClusterAnnotationView.swift`

**Responsibilities:** The visual pin shown when multiple contact pins are clustered together.

**Implementation notes:**
- Subclass `MKAnnotationView`
- In `didSet` on the `annotation` property, cast to `MKClusterAnnotation` and read `.memberAnnotations.count`
- Draw a filled circle with the count as a label inside it. Simplest approach: use a `UILabel` centered in the view with a circular `UIView` background
- Color: `UIColor.systemBlue` fill, white text
- Size: 40×40 pt
- Register in `MapViewController` via `mapView.register(ClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)`

---

## MapViewController

**File:** `Controllers/MapViewController.swift`

This is the root and only view controller. It owns the map, orchestrates the managers, and handles all UIKit delegate callbacks.

### Properties
```swift
private let mapView = MKMapView()
private let locationManager = CLLocationManager()
private let contactsManager = ContactsManager()
private let geocodingManager = GeocodingManager()
private var progressBanner: UIView?
private var progressLabel: UILabel?
private var didCenterOnUser = false
private var isRefreshing = false
private let contactChangeCoalescer = ContactChangeCoalescer()
private var contactChangeDebounceWorkItem: DispatchWorkItem?
```

### `viewDidLoad`
1. Add `mapView` as a full-screen subview (pin all edges to `view`, not safe area)
2. Set `mapView.delegate = self`
3. Set `mapView.showsUserLocation = true`
4. Register `ContactAnnotationView` and `ClusterAnnotationView` with the map view
5. Add an `MKUserTrackingButton` pinned to the bottom-right safe area
6. Configure `geocodingManager` callbacks (see below)
7. Request location authorization: `locationManager.delegate = self`, then `locationManager.requestWhenInUseAuthorization()`
8. Observe `CNContactStoreDidChange` notifications for live contact sync
9. Call `loadContacts()`

### `loadContacts()`
```swift
func loadContacts() {
    contactsManager.requestAccessAndFetch { [weak self] rawAddresses in
        Task { @MainActor [weak self] in
            guard let self else { return }
            if rawAddresses.isEmpty {
                // No geocoding will run, so unblock refreshes explicitly.
                if self.contactChangeCoalescer.noteInitialLoadComplete() {
                    self.scheduleContactRefresh()
                }
                self.showContactsAccessDeniedAlert()
                return
            }
            self.geocodingManager.process(
                addresses: rawAddresses,
                userLocation: self.locationManager.location?.coordinate
            )
        }
    }
}
```

### GeocodingManager callbacks
```swift
geocodingManager.onContactResolved = { [weak self] mappedContact in
    let annotation = ContactAnnotation(mappedContact: mappedContact)
    self?.mapView.addAnnotation(annotation)
}

geocodingManager.onProgress = { [weak self] completed, total in
    self?.updateProgressBanner(completed: completed, total: total)
}

geocodingManager.onComplete = { [weak self] failedCount in
    guard let self else { return }
    self.hideProgressBanner()
    self.centerOnAnnotationsIfNeeded()
    if failedCount > 0, !FeatureFlags.hideGeocodingToasts {
        self.showGeocodingFailureBanner(count: failedCount)
    }
    // Apply any contact store change that arrived during the initial load.
    if self.contactChangeCoalescer.noteInitialLoadComplete() {
        self.scheduleContactRefresh()
    }
}
```

### Live contact sync
- `contactStoreDidChange` asks `contactChangeCoalescer` what to do. During the initial load the change is recorded and deferred; afterwards it schedules a refresh through a 1-second debounce window.
- If a refresh is already in flight when the debounce fires, it reschedules rather than dropping the change.
- `refreshContacts()` cancels in-progress geocoding, re-fetches, and diffs.
- **An empty fetch result is not a deletion.** `diffAndUpdate` returns early when the fetch yields no addresses (revoked access, enumeration failure), because diffing against an empty list would remove every pin on the map.

### Progress Banner
- A simple `UIView` pinned to the bottom of the safe area, containing a `UILabel`
- Text: `"Mapping \(completed) of \(total) contacts..."`
- Show it before geocoding starts, hide it when `onComplete` fires
- Animate in/out with a 0.25s alpha fade
- Only show if there are cache misses (i.e. if `total > 0`)

### Map centering
- When the user's location becomes available (`CLLocationManagerDelegate.locationManager(_:didUpdateLocations:)`), call `mapView.setRegion(_:animated:)` centered on the user with a span of ~0.1 degrees
- Only do this on the first location update (use a `didCenterOnUser: Bool` flag)
- If location is denied or unavailable, center on the geographic midpoint of all plotted annotations after `onComplete` fires

### Contacts access denied alert
```swift
func showContactsAccessDeniedAlert() {
    let alert = UIAlertController(
        title: "Contacts Access Required",
        message: "Please enable Contacts access in Settings to use Map My Friends.",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
}
```

### `MKMapViewDelegate`
```swift
func mapView(_ mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
    // Return nil for the user location dot — MapKit handles it
    if annotation is MKUserLocation { return nil }
    // MapKit's dequeue handles ContactAnnotationView and ClusterAnnotationView
    // automatically because they are registered with default reuse identifiers
    return nil   // returning nil here lets the registered classes take over
}
```

> **Note:** Because both annotation view classes are registered with `MKMapViewDefaultAnnotationViewReuseIdentifier` and `MKMapViewDefaultClusterAnnotationViewReuseIdentifier`, returning `nil` from this delegate method is actually correct — MapKit will use the registered classes automatically. This is the modern MapKit pattern. Only override this method if you need custom logic per annotation.

---

## SwiftUI App Entry Point

```swift
@main
struct MapMyFriendsApp: App {
    var body: some Scene {
        WindowGroup {
            MapViewControllerWrapper()
                .ignoresSafeArea()
        }
    }
}
```

`MapViewControllerWrapper` is a `UIViewControllerRepresentable` that wraps `MapViewController` inside a `UINavigationController`.

---

## Threading Rules

Follow these strictly to avoid bugs:

- **CNContactStore fetch** → Background (`DispatchQueue.global(qos: .userInitiated)`)
- **MKGeocodingRequest calls** → Main thread (`@MainActor` on `GeocodingManager`)
- **CacheManager read/write** → Thread-safe via internal serial `DispatchQueue`
- **mapView.addAnnotation** → Main thread
- **All UI updates** → Main thread
- **ContactDiffer.diff()** → Pure function, callable from any thread

---

## Status of Originally Planned TODOs

1. ~~**Contact change detection**~~ — ✅ Implemented via `CNContactStoreDidChange` + `ContactDiffer`.
2. **Cache invalidation** — detect when a cached address no longer matches the contact's current address *(not yet implemented)*
3. **Refresh button** — nav bar button to manually re-fetch and re-geocode *(not yet implemented)*
4. ~~**Error state UI**~~ — ✅ Implemented. Auto-dismissing orange banner shows failed geocode count (gated by `hideGeocodingToasts` feature flag).
5. ~~**Contact avatar pins**~~ — Implemented but disabled pending fix (see TODO in `ContactAnnotationView`).
6. **Address type color coding** — different pin colors for Home vs Work vs Other *(not yet implemented)*
7. ~~**Call/Text from pin**~~ — ✅ Implemented. Action sheet with Call/Message (gated by `openContactOnPinTap` feature flag).
8. ~~**Open in Contacts**~~ — ✅ Implemented. Pushes `CNContactViewController` on pin tap (background fetch for speed).
9. ~~**About page**~~ — ✅ Implemented. SwiftUI `AboutView` with app icon and GitHub link.
10. ~~**Feature flags**~~ — ✅ Implemented. `Settings.bundle` with user-facing toggles backed by `UserDefaults`.
11. ~~**Cluster zoom**~~ — ✅ Implemented. Tapping a cluster zooms to its members; same-location clusters show a contact list.
12. ~~**Cache TTL**~~ — ✅ Implemented. 90-day TTL for successes. Failures are no longer cached at all (see below).
13. ~~**Proximity sorting**~~ — ✅ Implemented. Cache hits sorted by distance to user.
14. ~~**Incremental persistence**~~ — ✅ Implemented. Cache saves every 10 geocodes.

---

## Post-Launch Fixes: "Contacts stopped showing on the map"

Five bugs made previously-visible contacts disappear, plus a sixth found while fixing them. All are fixed; see the plan document `Contact Plotting Bug Analysis & Fix Plan` for the full analysis.

1. **Failed geocodes cached for 24 hours** — a single transient failure hid a contact until the entry expired. Failures are no longer cached; they retry every launch.
2. **`CNContactStoreDidChange` interrupted the initial geocode** — granting permission fired the notification mid-run, cancelling it and dropping every contact not yet geocoded. Changes during the initial load are now deferred and coalesced (`ContactChangeCoalescer`).
3. **Skipped contacts weren't counted** — `onComplete(0)` reported success while N contacts had been silently dropped. Replaced by a full `Summary` plus an always-on DEBUG log.
4. **`MKGeocodingRequest` init failures cached as permanent** — valid addresses could be marked failed over a formatting quirk. Never cached now.
5. **No observability with toasts hidden** — nothing indicated missing pins. Every run logs a breakdown in DEBUG.
6. **An empty fetch wiped every pin** — revoked access or a fetch error returned `[]`, and the diff removed all annotations. An empty fetch is now ignored.

Two structural changes came out of making these testable:
- **`AddressGeocoding` seam** — the pipeline can now be tested offline and deterministically; before, any cache miss hit the live network.
- **Loop instead of recursion** in the sequential walk — required once a synchronous test geocoder could drive 1000 addresses in one call.

---

## Testing Checklist

Automated coverage lives in `MapMyFriendsTests/test-plan.MD`. This checklist covers what only a device can confirm.

- [ ] First launch: contacts permission prompt appears
- [ ] First launch: progress banner appears and counts up
- [ ] First launch with 300 addresses: all pins appear within ~60 seconds
- [ ] First launch: granting permission does NOT restart or truncate the initial geocoding pass
- [ ] Second launch: all pins appear immediately with no progress banner
- [ ] Pin count matches the DEBUG `[GeocodingManager]` summary line (FromCache + Geocoded)
- [ ] Airplane mode on first launch: no pins cached as failed; disabling it and relaunching plots everything
- [ ] Editing several contacts in quick succession triggers exactly one refresh, with no duplicate pins
- [ ] Revoking contacts access while running does not clear pins already on the map
- [ ] Tapping a pin shows name and address label in callout
- [ ] Zooming out causes pins to cluster with a count badge
- [ ] Zooming in expands clusters back to individual pins
- [ ] Location permission granted: blue dot appears and map centers on user
- [ ] Location permission denied: map centers on midpoint of all pins
- [ ] Contacts permission denied: alert appears with link to Settings

---

Hand this to Claude Code or Warp as-is. The build order to follow is: Models → CacheManager → ContactsManager → GeocodingManager → ContactAnnotation → ContactAnnotationView → ClusterAnnotationView → MapViewController → SceneDelegate wiring → end-to-end test.