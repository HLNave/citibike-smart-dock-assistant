# Dock Finder

A minimal SwiftUI app that exposes a **Find Dock** App Intent to Siri and Shortcuts. It finds the nearest Citi Bike station that is accepting returns and has at least one open dock, using Citi Bike's public GBFS feeds.

> "Hey Siri, find a dock with Dock Finder."

## Layout

| Path | Purpose |
| --- | --- |
| `biker-app/App/DockFinderApp.swift` | Entry point; shows onboarding or home based on `OnboardingState` |
| `biker-app/Views/` | `WelcomeView` (+ onboarding flow), `SiriInstructionsView`, `HomeView`, shared `DockLookupSection` / `DockLookupModel` |
| `biker-app/Intents/` | `FindDockIntent`, `DockFinderShortcutsProvider` |
| `biker-app/Services/` | `DockFinderService` (pipeline + selection), `CitiBikeAPIClient` (GBFS), `LocationService` (one-shot When In Use), `DockFinderError` |
| `biker-app/Models/` | GBFS feed models, `DockStation` / `DockSearchResult` |
| `biker-app/State/OnboardingState.swift` | Persisted walkthrough flag (`UserDefaults`) |
| `DockFinderTests/` | Swift Testing unit tests |

Siri and the in-app buttons go through the same code: `DockFinderService.live.findNearestDock()`.

## How it works

1. Get one location fix (`CLLocationManager.requestLocation`, 15 s timeout, nothing persisted).
2. Fetch `station_information.json` and `station_status.json` concurrently from `gbfs.citibikenyc.com`.
3. Reject the status feed if `last_updated` is more than 15 minutes old.
4. Join on `station_id`. Keep stations that are installed, have `is_returning` set, have `num_docks_available > 0`, and reported within the last hour.
5. Pick the minimum **straight-line** distance. If it's more than 10 km away, report "outside service area".

Citi Bike publishes the GBFS booleans as `0`/`1` integers. The decoder accepts booleans, integers, or strings. A malformed station is skipped instead of failing the whole feed.

Distances are formatted for your locale (feet/miles in the US). They are always described as "in a straight line", never as a route distance.

## Building

- Xcode 26.6, iOS 26.5 deployment target (from the existing project).
- **Set a Development Team** (target `biker-app` → Signing & Capabilities). Without a Team ID, iOS's App Intents daemon (`linkd`) rejects the app, with "Unable to get teamId … Rejecting invalid client due to requiresValidBundle". Find Dock still *appears* in Shortcuts but fails with "Unable to run App Shortcut". This happens in the Simulator too.

```bash
xcodebuild -project biker-app.xcodeproj -scheme biker-app -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

To also run the opt-in test against the live Citi Bike feeds:

```bash
TEST_RUNNER_DOCKFINDER_LIVE_TESTS=1 xcodebuild -project biker-app.xcodeproj -scheme biker-app -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Manual verification checklist (physical iPhone)

These can't be automated and **have not yet been verified on a device**:

- [ ] Fresh install → Welcome screen → button shows the location prompt → Siri instructions screen.
- [ ] `SiriTipView` shows the phrase. It renders as a placeholder in the Simulator.
- [ ] "Dock Finder shortcuts" link opens Shortcuts and shows **Find Dock**.
- [ ] Running Find Dock from Shortcuts speaks or shows a real station.
- [ ] "Hey Siri, find a dock with Dock Finder" works **without opening the app** (`supportedModes = .background`).
- [ ] Location permission never granted → Siri says to open Dock Finder.
- [ ] Location revoked in Settings → Siri reports permission denied, and the app shows the Settings notice.
- [ ] Airplane mode → "couldn't reach Citi Bike".
- [ ] Approximate location only → result includes the "location is approximate" caveat.

If the background location fix turns out to be unavailable to the intent on device, switch `supportedModes` to `[.background, .foreground(.dynamic)]` and call `continueInForeground` before retrying. In-process App Intents are expected to have When In Use access while running, but only a device test can confirm that.

## Reference shortcuts (analysis)

The three supplied `.shortcut` files are signed Apple Encrypted Archives. They were decoded with `aea decrypt -sign-pub` (using the key from the embedded signing certificate) followed by `aa extract`.

**Dock Finder.shortcut**: Ask for Input ("What do you need?") → Get Current Location → `POST https://YOUR-N8N-HOST/webhook/citibike-siri` with `{text, lat, lon, sessionId: "<name>"}` → Speak the response.

- All station-selection logic lives in the remote n8n workflow, which isn't included. There was no algorithm in the shortcut to preserve.
- Differences in the native app:
  - No free-text question: the intent always answers "nearest station with an open return dock".
  - No third-party backend: the data comes straight from Citi Bike's GBFS feeds.
  - No hardcoded session ID.
  - Behavior is deterministic and covered by unit tests.
- If the n8n workflow did more (for example finding bikes, e-bikes, or ranking by more than distance), that behavior isn't reproduced here.

**School Automation.shortcut** + **CitiBike App Detection.shortcut**: a personal-automation pair.

- *App Detection* (presumably triggered when the Citi Bike app opens) writes the current ISO-8601 timestamp to `ride.txt`.
- *School Automation* (presumably a location trigger) reads `ride.txt`. If more than 60 minutes have passed, it exits. Otherwise it geocodes "44 W 4th Street", POSTs `{place: "school", destLat, destLon}` to `…/webhook/citibike-arrival`, speaks the response, and resets `ride.txt` to `2000-01-01`.
- These are user-created automations and aren't installed or recreated by the app (out of scope per the PRD). A future "dock near my destination" intent could cover the same need natively.
