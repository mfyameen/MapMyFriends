Here's a thorough engineering spec you can hand directly to Claude Code or Warp:

---

# Map My Friends — Engineering Spec

## Project Overview

An iOS app (UIKit) that reads a user's phone contacts, geocodes their addresses, and plots them as clustered pins on a full-screen map. The user's own location is shown as a blue dot. Tapping a pin shows the contact's name and address type. All geocoding results are cached locally so subsequent launches are near-instant.

**Target: iOS 16+, Swift 5.9, UIKit, no third-party dependencies.**

---

## Xcode Project Setup

- Create a new Xcode project: App template, Swift, UIKit, no CoreData, no SwiftUI
- Product name: `MapMyFriends`
- Bundle ID: `com.yourname.MapMyFriends`
- Delete `Main.storyboard`. Remove the "Main" entry from the project's Info.plist under "UISceneStoryboardFile" and "NSPrincipalClass" storyboard references
- Set up the window programmatically in `SceneDelegate.swift`
- Minimum deployment target: iOS 16.0

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
├── AppDelegate.swift
├── SceneDelegate.swift
├── Controllers/
│   └── MapViewController.swift
├── Managers/
│   ├── ContactsManager.swift
│   ├── GeocodingManager.swift
│   └── CacheManager.swift
├── Models/
│   ├── MappedContact.swift
│   └── CachedCoordinate.swift
├── Views/
│   ├── ContactAnnotation.swift
│   ├── ContactAnnotationView.swift
│   └── ClusterAnnotationView.swift
└── Info.plist
```

---

## Models

### `MappedContact.swift`
```swift
import CoreLocation

struct MappedContact {
    let contactID: String        // CNContact.identifier
    let fullName: String
    let addressLabel: String     // "Home", "Work", "Other", etc.
    let addressString: String    // raw formatted address, used as cache key
    let coordinate: CLLocationCoordinate2D
}
```

### `CachedCoordinate.swift`
```swift
import Foundation

struct CachedCoordinate: Codable {
    let lat: Double
    let lng: Double
    let cachedAt: Date
}
```

---

## CacheManager

**File:** `Managers/CacheManager.swift`

**Responsibilities:** Read and write a JSON file that maps raw address strings to `CachedCoordinate` values. This is the sole persistence layer.

**Cache file location:** `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first` + `address_cache.json`

**Public interface:**
```swift
class CacheManager {
    static let shared = CacheManager()

    // Load full cache dictionary from disk into memory on init
    private var cache: [String: CachedCoordinate] = [:]

    func coordinate(for address: String) -> CachedCoordinate?
    func store(coordinate: CachedCoordinate, for address: String)
    func saveToDisc()   // write full cache dict to JSON file
}
```

**Implementation notes:**
- Load the JSON file in `init()` using `JSONDecoder`. If the file doesn't exist yet, start with an empty dictionary.
- `store(coordinate:for:)` updates the in-memory dictionary and immediately calls `saveToDisk()`.
- `saveToDisk()` encodes the full dictionary with `JSONEncoder` and writes to the file path using `Data.write(to:options:.atomic)`. Atomic write prevents corruption if the app is killed mid-write.
- The cache dictionary key is the raw address string exactly as it comes from `CNPostalAddressFormatter`. No normalization needed — consistency of the key is what matters.
- No cache expiry for now. Entries persist indefinitely.

---

## ContactsManager

**File:** `Managers/ContactsManager.swift`

**Responsibilities:** Request Contacts permission, fetch all contacts that have at least one postal address, and return them as an array of raw data ready for geocoding.

**Public interface:**
```swift
class ContactsManager {

    struct RawContactAddress {
        let contactID: String
        let fullName: String
        let addressLabel: String    // human-readable label
        let addressString: String   // formatted for geocoding
    }

    func requestAccessAndFetch(completion: @escaping ([RawContactAddress]) -> Void)
}
```

**Implementation notes:**
- Use `CNContactStore().requestAccess(for: .contacts)` to prompt the user.
- If access is denied, call `completion([])` and surface an alert in `MapViewController` (see below).
- Fetch using `CNContactFetchRequest` with these keys to request: `[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPostalAddressesKey, CNContactIdentifierKey]`
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
class GeocodingManager {

    // Called for each successfully resolved contact (may be called many times)
    var onContactResolved: ((MappedContact) -> Void)?

    // Called with (completed, total) after each geocode attempt
    var onProgress: ((Int, Int) -> Void)?

    // Called when all addresses have been processed
    var onComplete: (() -> Void)?

    func process(addresses: [ContactsManager.RawContactAddress])
    func cancel()
}
```

**Implementation notes:**
- On `process(addresses:)`, first separate the list into cache hits and cache misses.
- For cache hits: immediately call `onContactResolved` for each (synchronously or with a trivial async dispatch — just don't block).
- For cache misses: geocode sequentially using `CLGeocoder().geocodeAddressString(_:completionHandler:)`. Do NOT geocode in parallel — Apple rate-limits `CLGeocoder` aggressively and parallel calls will fail.
- Between each geocode call, add a `0.15` second delay using `DispatchQueue.main.asyncAfter` or `Task.sleep` to stay well under the rate limit.
- If a geocode succeeds, take `placemarks.first?.location?.coordinate`, construct a `MappedContact`, store it in `CacheManager`, and call `onContactResolved`.
- If a geocode fails (nil placemark, or error), log the failure and skip — do not retry. The address will be attempted again on next launch since it won't be in the cache.
- Call `onProgress(completedCount, totalMissCount)` after each geocode attempt (success or failure).
- When all misses are processed, call `onComplete`.
- Implement `cancel()` by setting a `isCancelled: Bool` flag that is checked before each sequential geocode step.
- All callbacks should be delivered on the main thread.

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
- Set `clusteringIdentifier = "contact"` — this single line enables MapKit's native clustering
- `markerTintColor`: use a consistent app color (e.g. `UIColor.systemBlue`)
- `glyphImage`: optionally use a person SF Symbol (`UIImage(systemName: "person.fill")`)
- `canShowCallout = true` — enables the built-in tap callout bubble with title and subtitle automatically
- `rightCalloutAccessoryView`: optionally add a `UIButton(type: .detailDisclosure)` as a placeholder for future deep-dive (no action needed now)
- Register this class in `MapViewController` via `mapView.register(ContactAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)`

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
private var progressBanner: UIView?        // shown during first-run geocoding
private var progressLabel: UILabel?
```

### `viewDidLoad`
1. Add `mapView` as a full-screen subview (pin all edges to `view`, not safe area)
2. Set `mapView.delegate = self`
3. Set `mapView.showsUserLocation = true`
4. Register `ContactAnnotationView` and `ClusterAnnotationView` with the map view
5. Configure `geocodingManager` callbacks (see below)
6. Request location authorization: `locationManager.delegate = self`, then `locationManager.requestWhenInUseAuthorization()`
7. Call `loadContacts()`

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

## SceneDelegate Setup

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)
    window?.rootViewController = MapViewController()
    window?.makeKeyAndVisible()
}
```

---

## Threading Rules

Follow these strictly to avoid bugs:

| Operation | Thread |
|---|---|
| CNContactStore fetch | Background (`DispatchQueue.global`) |
| CLGeocoder calls | Main thread (CLGeocoder requirement) |
| CacheManager read/write | Main thread (no locking needed at this scale) |
| mapView.addAnnotation | Main thread |
| All UI updates | Main thread |

---

## Known TODOs (do not implement now, but leave a `// TODO:` comment)

1. **Contact change detection** — re-geocode when CNContactStore posts `CNContactStoreDidChangeNotification`
2. **Cache invalidation** — detect when a cached address string no longer matches the contact's current address
3. **Refresh button** — a nav bar button to manually re-fetch contacts and re-geocode changed addresses
4. **Error state UI** — surface geocoding failure count to the user ("3 addresses could not be mapped")
5. **Contact avatar pins** — replace `MKMarkerAnnotationView` with a circular contact photo
6. **Address type color coding** — different pin colors for Home vs Work vs Other

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