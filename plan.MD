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
├── Controllers/
│   └── MapViewController.swift       # Root UIKit VC — map, location, orchestration
├── Managers/
│   ├── CacheManager.swift            # JSON cache with CacheManaging protocol & thread-safe queue
│   ├── ContactsManager.swift         # Contacts permission & fetch (incl. thumbnails)
│   ├── ContactDiffer.swift           # Pure-function diff for live contact sync
│   └── GeocodingManager.swift        # Sequential geocoding via MKGeocodingRequest
├── Models/
│   ├── MappedContact.swift           # Contact + coordinate + optional thumbnail
│   └── CachedCoordinate.swift        # Codable lat/lng/timestamp
├── Views/
│   ├── ContactAnnotation.swift       # MKAnnotation wrapper
│   ├── ContactAnnotationView.swift   # Person pin with avatar support & clustering
│   ├── ClusterAnnotationView.swift   # Circle with count badge
│   └── MapViewControllerWrapper.swift # UIViewControllerRepresentable bridge
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
    let failed: Bool    // true if geocoding failed; uses shorter TTL (24h vs 90d)
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
- **Dual TTL**: Successful entries expire after 90 days (`cacheTTL`). Failed entries use a 24-hour TTL (`failedTTL`) so transient geocoding failures are retried sooner. Both TTLs are injectable via `init(fileURL:ttl:failedTtl:)` for testing.
- `coordinate(for:)` checks the entry's age against the appropriate TTL and returns `nil` for stale entries.

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

    var onContactResolved: ((MappedContact) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    /// Parameter is the number of addresses that failed to geocode.
    var onComplete: ((Int) -> Void)?

    private let cache: CacheManaging
    private var currentRequest: MKGeocodingRequest?

    init(cache: CacheManaging = CacheManager.shared)
    func process(addresses: [ContactsManager.RawContactAddress], userLocation: CLLocationCoordinate2D? = nil)
    func cancel()
}
```

**Implementation notes:**
- The class is `@MainActor`-isolated. It accepts a `CacheManaging` dependency via init (defaults to `CacheManager.shared`) for testability.
- On `process(addresses:userLocation:)`, classify each address in a **single cache lookup**: cache hit (resolve immediately), failed entry (`continue` — skip silently, short TTL will retry), or cache miss (geocode). This single-lookup approach eliminates a previous double-lookup race condition.
- If `userLocation` is provided, resolved cache hits are sorted by proximity so nearby pins appear first.
- For cache misses: geocode sequentially using `MKGeocodingRequest(addressString:)` and `.getMapItems()`. Do NOT geocode in parallel — Apple rate-limits geocoding aggressively.
- If `MKGeocodingRequest(addressString:)` returns nil (invalid address string), cache it as `failed: true` and increment `failedCount`.
- Between each geocode call, add a `0.15` second delay using `DispatchQueue.main.asyncAfter`.
- If a geocode succeeds, store the result in the cache and call `onContactResolved`.
- If a geocode fails (nil result or error), cache the failure as `failed: true` with a fresh timestamp (24h retry via `failedTTL`).
- **Incremental persistence**: `cache.saveToDisk()` is called every 10 geocodes, plus on completion and on cancel.
- `onComplete(failedCount)` reports the number of addresses that failed to geocode.
- All callbacks are delivered on the main thread (guaranteed by `@MainActor` isolation).

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
        guard let self else { return }
        if rawAddresses.isEmpty {
            self.showContactsAccessDeniedAlert()
            return
        }
        self.geocodingManager.process(addresses: rawAddresses)
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

geocodingManager.onComplete = { [weak self] in
    self?.hideProgressBanner()
}
```

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
12. ~~**Cache TTL**~~ — ✅ Implemented. 90-day TTL for successes, 24-hour TTL for failures.
13. ~~**Proximity sorting**~~ — ✅ Implemented. Cache hits sorted by distance to user.
14. ~~**Incremental persistence**~~ — ✅ Implemented. Cache saves every 10 geocodes.

---

## Testing Checklist

- [ ] First launch: contacts permission prompt appears
- [ ] First launch: progress banner appears and counts up
- [ ] First launch with 300 addresses: all pins appear within ~60 seconds
- [ ] Second launch: all pins appear immediately with no progress banner
- [ ] Tapping a pin shows name and address label in callout
- [ ] Zooming out causes pins to cluster with a count badge
- [ ] Zooming in expands clusters back to individual pins
- [ ] Location permission granted: blue dot appears and map centers on user
- [ ] Location permission denied: map centers on midpoint of all pins
- [ ] Contacts permission denied: alert appears with link to Settings

---

Hand this to Claude Code or Warp as-is. The build order to follow is: Models → CacheManager → ContactsManager → GeocodingManager → ContactAnnotation → ContactAnnotationView → ClusterAnnotationView → MapViewController → SceneDelegate wiring → end-to-end test.