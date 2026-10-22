# On-device checklist (before submitting)

Everything below was tested in the simulator; these are the things that behave differently on a real iPhone. Takes about 15 minutes.

## Install

1. Plug in the iPhone, unlock it, and tap **Trust** if asked. Developer Mode must be on (Settings → Privacy & Security → Developer Mode).
2. In Xcode, pick the iPhone as the run destination and press Run. Signing uses your Apple Development certificate; Xcode registers the device automatically.
3. First time only: on the iPhone, go to Settings → General → VPN & Device Management and trust your developer certificate.

For a truly first-launch run, delete the app first so both permission prompts appear again.

## Checks

**Permissions**
- [ ] First launch asks for **Contacts only**. The Location prompt appears after the pins are on the map, not straight after the Contacts one.
- [ ] Choosing **Select Contacts** (limited access) with no address-bearing contacts shows the "No addresses in the contacts you shared" card. **Share More Contacts** opens Apple's picker; adding someone with an address makes their pin appear without relaunching. (This picker crashed in the simulator before a fix; it can't be tested any other way.)
- [ ] Denying Contacts shows the alert, then the "Contacts access is off" card stays after dismissing it.

**Map and location**
- [ ] With Location allowed, the map centers on you once. Panning before that happens keeps the map where you put it.
- [ ] The blue dot keeps following you as you move, even though the app stops its own location updates after the first fix.

**Pins**
- [ ] Contacts with photos show their photo; names under pins are readable in light and dark mode.
- [ ] Tapping a pin's info button: with "Open Contact on Tap" off (the default), Call and Message work. Try a number with an extension (e.g. `555-1234 ext. 12`) and check the call dials the extension after a pause.
- [ ] "N not on the map" lists anyone whose address couldn't be found; tapping one opens their card with Edit. Fixing the address and saving makes their pin appear.

**VoiceOver** (Settings → Accessibility → VoiceOver, or triple-click the side button if set up)
- [ ] Swiping through pins reads "name, label, address"; clusters read "N contacts" with a hint.

**Cache while locked**
- [ ] Open the app, lock the phone for a minute, unlock, and reopen: pins load instantly with no new lookups.
- [ ] Quit the app, lock the phone for a minute, then open the app from the lock screen widget or right after unlocking: no pins go missing.

If anything fails, note what you saw and send it over.
