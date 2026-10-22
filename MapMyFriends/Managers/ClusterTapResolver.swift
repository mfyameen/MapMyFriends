//
//  ClusterTapResolver.swift
//  MapMyFriends
//

import MapKit

/// Decides what tapping a cluster does. Extracted from `MapViewController` so the
/// decision is unit-testable without a live map.
enum ClusterTapResolver {

    enum Action: Equatable {
        /// Zooming can't separate the members, so list them instead.
        case showList
        /// Zoom the map to this rect so the cluster splits apart.
        case zoom(to: MKMapRect)

        static func == (lhs: Action, rhs: Action) -> Bool {
            switch (lhs, rhs) {
            case (.showList, .showList): true
            case let (.zoom(a), .zoom(b)): MKMapRectEqualToRect(a, b)
            default: false
            }
        }
    }

    /// The order contacts appear in when a cluster is listed: by name the way people read it
    /// ("Worker2" before "Worker10", case ignored), then by address so the list is stable.
    static func listOrder(_ contacts: [MappedContact]) -> [MappedContact] {
        contacts.sorted { a, b in
            switch a.fullName.localizedStandardCompare(b.fullName) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.addressString.localizedStandardCompare(b.addressString) == .orderedAscending
            }
        }
    }

    /// Below this latitude span (~200 m) the map is at or near maximum zoom, so a cluster
    /// that still exists won't split apart however far the user zooms.
    static let maxZoomSpan: CLLocationDegrees = 0.002

    /// - Parameters:
    ///   - members: Coordinates of every annotation in the cluster.
    ///   - clusterCoordinate: Where the cluster itself is drawn.
    ///   - visibleSpan: The map's current latitude span in degrees.
    static func action(
        members: [CLLocationCoordinate2D],
        clusterCoordinate: CLLocationCoordinate2D,
        visibleSpan: CLLocationDegrees
    ) -> Action {
        let allSameLocation = members.allSatisfy { member in
            let latDiff = abs(member.latitude - clusterCoordinate.latitude)
            let lngDiff = abs(member.longitude - clusterCoordinate.longitude)
            return latDiff < 0.0001 && lngDiff < 0.0001
        }

        // No member limit: any contact left out here couldn't be reached at all.
        if allSameLocation || visibleSpan <= maxZoomSpan {
            return .showList
        }

        let rect = members.reduce(MKMapRect.null) { rect, member in
            let point = MKMapPoint(member)
            return rect.union(MKMapRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200))
        }
        return .zoom(to: rect)
    }
}
