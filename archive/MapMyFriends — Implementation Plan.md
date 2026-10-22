# MapMyFriends — Implementation Plan
> **Status: completed — historical record.** This is the original build-out plan; every step shipped. It describes the app as first assembled, not as it stands now. For current architecture see `README.md`, and for the full spec see `plan.MD`.
## Summary
iOS app that reads contacts, geocodes addresses, and plots them as clustered pins on a map\. SwiftUI app lifecycle hosting a UIKit MapViewController\. Swift 6 strict concurrency\. iOS 26\.4 target\.
## Key Decisions
* **App lifecycle**: Keep SwiftUI entry point \(`MapMyFriendsApp.swift`\), host UIKit via `UIViewControllerRepresentable`
* **Concurrency**: Swift 6 strict \(`MainActor` default isolation\) — use `nonisolated`, `@Sendable` where needed
* **Cache saves**: Batch — save on `onComplete` and `cancel()`, not per\-store
* **Navigation**: Wrap `MapViewController` in `UINavigationController` for future refresh button
* **Deployment target**: iOS 26\.4 \(unchanged\)
* **Info\.plist**: Add privacy keys via build settings in `.pbxproj`
## Current State
* Xcode project exists with SwiftUI template \(`MapMyFriendsApp.swift`, `ContentView.swift`\)
* `PBXFileSystemSynchronizedRootGroup` — files auto\-discovered by Xcode
* No source files beyond the template
## File Changes
### Delete
* `MapMyFriends/ContentView.swift` — replaced by MapViewControllerWrapper
### Modify
* `MapMyFriends/MapMyFriendsApp.swift` — swap `ContentView()` for `MapViewControllerWrapper()` wrapped in nav
* `MapMyFriends.xcodeproj/project.pbxproj` — add `INFOPLIST_KEY_NSContactsUsageDescription` and `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` to both Debug and Release build configs
### Create \(all under `MapMyFriends/MapMyFriends/`\)
**Models/**
* `MappedContact.swift` — struct with contactID, fullName, addressLabel, addressString, coordinate
* `CachedCoordinate.swift` — Codable struct with lat, lng, cachedAt
**Managers/**
* `CacheManager.swift` — singleton, JSON file in documents dir, batch save via `saveToDisk()` \(called explicitly, not on every store\)
* `ContactsManager.swift` — request contacts access, fetch all contacts with postal addresses, return `[RawContactAddress]`\. Mark fetch as `nonisolated` for background work, deliver results on MainActor\.
* `GeocodingManager.swift` — sequential geocoding with 0\.15s delay, cache check, progressive callbacks\. Uses `@MainActor` for callbacks, `nonisolated` not needed since CLGeocoder runs fine on main thread\.
**Views/**
* `ContactAnnotation.swift` — MKAnnotation subclass wrapping MappedContact
* `ContactAnnotationView.swift` — MKMarkerAnnotationView subclass, clusteringIdentifier = "contact"
* `ClusterAnnotationView.swift` — MKAnnotationView subclass, draws circle with count
* `MapViewControllerWrapper.swift` — UIViewControllerRepresentable bridging MapViewController into SwiftUI
**Controllers/**
* `MapViewController.swift` — root UIKit VC: owns MKMapView, CLLocationManager, orchestrates managers, progress banner, handles MKMapViewDelegate and CLLocationManagerDelegate
## Build Order \(all complete ✅\)
1. ✅ Models \(MappedContact, CachedCoordinate\)
2. ✅ CacheManager
3. ✅ ContactsManager
4. ✅ GeocodingManager — uses MKGeocodingRequest \(CLGeocoder deprecated in iOS 26\)
5. ✅ ContactAnnotation, ContactAnnotationView, ClusterAnnotationView
6. ✅ MapViewController
7. ✅ MapViewControllerWrapper
8. ✅ Update MapMyFriendsApp\.swift, delete ContentView\.swift
9. ✅ Add Info\.plist privacy keys to pbxproj
10. ✅ Build & verify — clean build, zero warnings
