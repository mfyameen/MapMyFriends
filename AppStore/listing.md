# App Store Listing — Map My Friends (v1.0)

First draft of everything App Store Connect asks for. Character limits are noted; current counts are in brackets.

## App Information

| Field | Value |
|---|---|
| Name (30) | Map My Friends [14] |
| Subtitle (30) | See your contacts on a map [26] |
| Bundle ID | com.Rosedale.MapMyFriends |
| SKU | ROSEDALE-MAPMYFRIENDS-001 |
| Primary language | English (U.S.) |
| Primary category | Social Networking |
| Secondary category | Navigation |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ (answer "No" / "None" to every questionnaire item; no web browsing, no user-generated content, no messaging between users) |
| Copyright | © 2026 Rosedale Co |
| Seller / developer name | Rosedale Co |

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | https://mfyameen.github.io/MapMyFriends/privacy.html |
| Support URL | https://mfyameen.github.io/MapMyFriends/ |
| Marketing URL (optional) | https://github.com/mfyameen/MapMyFriends |

These URLs work once GitHub Pages is turned on for the repo (Settings → Pages → Deploy from branch → `main` / `/docs`).

## Promotional Text (170)

> See where everyone you know lives. Map My Friends turns your contacts into a map, so you can spot friends nearby wherever you are. No account, no tracking.

## Description (4000)

> Map My Friends shows the people in your contacts on a map.
>
> Traveling for work? Moved to a new city? Exploring a new neighborhood? Open the app and see which friends, family, and colleagues live nearby. Every contact with an address becomes a pin, so you can find out who's close by.
>
> HOW IT WORKS
> • Reads the addresses already saved in your contacts and pins them on the map
> • Shows your location as a blue dot, with the nearest contacts loaded first
> • Groups nearby pins into clusters that expand as you zoom in
> • When several contacts share an address, tap the cluster to see them all in a list
> • Tap a pin to open the contact, or call or message them right away
> • Updates the map automatically when you add, edit, or delete a contact
> • Remembers locations it has already found, so later launches are nearly instant
>
> PRIVATE BY DESIGN
> • No account, no sign-up, no ads, no analytics, no tracking
> • Your contacts stay on your device. Only addresses are sent to Apple Maps to find their location.
> • Saved locations are stored on your device with iOS Data Protection
> • Built entirely with Apple frameworks. No third-party code.
>
> OPEN SOURCE
> Map My Friends is fully open-source. You can read every line of code on GitHub.
>
> Note: The map shows the addresses saved in your contacts. It does not show anyone's real-time location.

## Keywords (100)

```
contacts,friends,family,nearby,address,people,travel,pins,neighbors,network,locate,who,near,me,book
```

Don't repeat words already in the name or subtitle (map, my, see, your, on, a); Apple indexes those anyway.

## What's New (version 1.0)

Leave blank on the first release.

## App Privacy (privacy "nutrition label")

- **Data collection:** select **"No, we do not collect data from this app."** The result is the **Data Not Collected** label.
- Why this is accurate: the developer gets no data, and the app has no server, analytics, or third-party SDKs. Contact addresses are sent only to Apple's own geocoding service through MapKit. Under Apple's definition, data processed by Apple frameworks isn't "collected" by the developer.
- Tracking: **No**.

## App Review Information

| Field | Value |
|---|---|
| Sign-in required | No |
| Contact name / phone / email | *(fill in: required by Apple, not shown publicly)* |

**Notes for the reviewer:**

> Map My Friends plots the postal addresses in the user's Contacts on a map. No account or sign-in is needed.
>
> PERMISSIONS
> • Contacts: required. This is the app's core feature, used to read contact names, postal addresses, phone numbers, and thumbnails for the map pins. Contact data is never sent to our servers (we don't have any). Only the postal address text is sent to Apple's MapKit geocoding service to get coordinates.
> • Location (When In Use): optional. It shows the user's blue dot and loads nearby contacts first. The app works without it.
>
> HOW TO TEST
> 1. Launch the app and allow Contacts access (and optionally Location).
> 2. Contacts that have a postal address appear as pins. If the test device has no contacts with addresses, add one in the Contacts app (for example 1 Apple Park Way, Cupertino, CA). The app picks up the change automatically while it is open.
> 3. Tap a pin, then tap its info button to open the contact. In iOS Settings → Apps → Map My Friends, turn off "Open Contact on Tap" to see the Call / Message menu instead.
> 4. Tap the info (ⓘ) button in the navigation bar to open the About page.

## Pricing & Availability

- Price: Free *(confirm)*
- Availability: all countries and regions *(confirm)*
- Distribution: Public on the App Store

## Screenshots

Ready to upload: [`AppStore/screenshots/`](screenshots/). Five 6.9" iPhone screenshots (1320 × 2868, JPEG, no transparency), taken in the iPhone 17 Pro Max simulator with made-up San Francisco contacts and illustrated avatars, so no real person appears. Upload them in this order:

1. `1-city.jpg`: the city with photo pins, names and clusters
2. `2-callout.jpg`: a contact's callout with their address
3. `3-call-message.jpg`: the Call / Message sheet
4. `4-same-address.jpg`: "4 contacts here", several people at one address
5. `5-privacy.jpg`: the About page and its privacy promise

Smaller iPhone sizes are scaled down from these automatically. No iPad screenshots are needed, since the app is iPhone-only.

## Export Compliance

`ITSAppUsesNonExemptEncryption = NO` is set in the build, so App Store Connect won't ask about encryption when you upload.
