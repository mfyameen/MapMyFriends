# MapMyFriends Security Fixes
This plan addresses the high and medium severity security issues found in the project\.
## 🔴 \#1 — Sensitive PII stored unencrypted on disk
`CacheManager.swift` writes contact addresses and GPS coordinates as plain\-text JSON to the Documents directory with no iOS Data Protection\.
**Fix:** Add `.completeFileProtection` to the file write options in `saveToDisk()`\.
## 🔴 \#2 — PII logged to console in production
`print()` calls in `ContactsManager.swift:75`, `GeocodingManager.swift:79`, and `GeocodingManager.swift:108` log raw contact addresses\. These persist in device logs accessible outside the app\.
**Fix:** Wrap all three `print()` calls in `#if DEBUG` so they are stripped from release builds\.
## 🟠 \#3 — No thread safety on shared mutable state
* `CacheManager.cache` is read/written from multiple threads with no synchronization\.
* `GeocodingManager.isCancelled` and `currentRequest` are accessed from different threads without protection\.
**Fix:**
* Protect `CacheManager.cache` with a private serial `DispatchQueue`, synchronizing all reads and writes\.
* Annotate `GeocodingManager` with `@MainActor` since its callbacks and sequential geocoding already run on the main thread, and `cancel()` should also be called from main\.
## 🟠 \#5 — No `.gitignore` file
No `.gitignore` exists\. `.DS_Store` and `xcuserdata` are already committed\.
**Fix:** Add a standard Swift/iOS `.gitignore`\. Remove `.DS_Store` from tracking with `git rm --cached`\.