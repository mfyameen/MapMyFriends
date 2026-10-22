//
//  InitialCameraPolicy.swift
//  MapMyFriends
//

/// Decides when the map may move on its own.
///
/// At launch the map frames the user's surroundings, or, without a location fix, every
/// contact. After that it must stay wherever the user put it: contact edits and foreground
/// retries finish geocoding runs too, and re-framing on each of those yanked the map away.
/// Once the user pans, zooms or taps a cluster, the map never moves on its own at all — the
/// first location fix often arrives after they've started exploring.
struct InitialCameraPolicy {

    private var hasCenteredOnUser = false
    private var hasFramedContacts = false
    private var userMovedMap = false

    /// The user panned, zoomed or tapped a cluster.
    mutating func noteUserMovedMap() {
        userMovedMap = true
    }

    /// `true` the first time only. A late first fix still wins over an earlier contact framing.
    mutating func shouldCenterOnUser() -> Bool {
        guard !userMovedMap, !hasCenteredOnUser else { return false }
        hasCenteredOnUser = true
        return true
    }

    /// `true` the first time only, and never once the map has centered on the user.
    mutating func shouldFrameContacts() -> Bool {
        guard !userMovedMap, !hasCenteredOnUser, !hasFramedContacts else { return false }
        hasFramedContacts = true
        return true
    }
}
