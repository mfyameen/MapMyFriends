//
//  InitialCameraPolicy.swift
//  MapMyFriends
//

/// Decides when the map may move on its own.
///
/// At launch the map frames the user's surroundings, or, without a location fix, every
/// contact. After that it must stay wherever the user put it: contact edits and foreground
/// retries finish geocoding runs too, and re-framing on each of those yanked the map away.
struct InitialCameraPolicy {

    private var hasCenteredOnUser = false
    private var hasFramedContacts = false

    /// `true` the first time only. A late first fix still wins over an earlier contact framing.
    mutating func shouldCenterOnUser() -> Bool {
        guard !hasCenteredOnUser else { return false }
        hasCenteredOnUser = true
        return true
    }

    /// `true` the first time only, and never once the map has centered on the user.
    mutating func shouldFrameContacts() -> Bool {
        guard !hasCenteredOnUser, !hasFramedContacts else { return false }
        hasFramedContacts = true
        return true
    }
}
