# Dock Finder

A SwiftUI app that answers Citi Bike dock questions through Siri, Shortcuts and its own screens. Everything that can run on the iPhone does. It reads Citi Bike's public GBFS feeds directly and uses Apple's map search for places. Only free-form questions the phone can't understand go to the group's n8n workflow.

> "Hey Siri, ask Dock Finder."
> Siri: "Where are you headed, or which station?"
> "School."
> Siri: "Your usual dock is full. Go to Washington and Greene, 8 docks, 350 feet from school."

## Using it with Siri

**"Hey Siri, ask Dock Finder"** (or "talk to Dock Finder") is the main phrase. It works with the phone locked. Siri asks "Where are you headed, or which station?", and you answer with:

- a ride: "start a ride to school", "I'm riding to Union Square" (see [Rides](#rides))
- a saved place: "school", "my work dock"
- any place: "near Union Square", "find a dock by NYU Stern"
- a station: "Mercer and Bleecker", "is West 15th and 6th full?"
- "near me"
- "how many bikes are out?"
- a setting: "my school dock is Mercer and Bleecker", "save this spot as gym", "end my ride"

Splitting it into two steps is more reliable than one long phrase. Siri only has to recognize "ask Dock Finder", and your answer goes to the app as plain text, so Siri can't turn it into a Maps search. ("Dock" sounds like "doc", so "find a dock near school" can come out as a search for doctors.) The app treats a dictated "doc" as "dock", and "Doc Finder" is registered as an alternate app name (`INAlternativeAppNames` in `Config/Info.plist`).

One-step phrases ("Find a dock with Dock Finder", "Find a dock near school with Dock Finder", "Check a station with Dock Finder", "Citi Bike status in Dock Finder") still work and are faster when Siri hears them correctly.

> **Why not "run Dock Finder"?** Siri treats "run", "open", "launch" or "start" plus an app's name as "open the app", which beats the app's own phrases and needs the phone unlocked. App phrases must include the app's name, so no "run …" phrase can work from the app itself.
>
> **If you'd rather say "run …"**, make a personal shortcut: Shortcuts app → **+** → add Dock Finder's **Ask Dock Finder** action → name the shortcut something other than "Dock Finder", e.g. **Dock Check**. Then "Hey Siri, run Dock Check" (or just "Hey Siri, Dock Check") works the same way, locked or not. One person can build it and share the iCloud link with the group.
>
> **If you set up the group's Shortcuts version** (`docs/iphone-setup-handoff.md`), you can delete your personal **Dock Finder** shortcut. With the app installed, "run Dock Finder" opens the app instead of running it.

## What runs where

| Feature | Runs on | Siri phrase |
| --- | --- | --- |
| Nearest dock to you | iPhone | "Ask Dock Finder" → "near me" (or "Find a dock with Dock Finder") |
| Dock near a saved place (school, work, home…), checking your usual dock first and rerouting if it's full | iPhone | "Ask Dock Finder" → "school" (or one step: "Find a dock near school with Dock Finder") |
| **Ride alert**: start a ride to a saved place or anywhere, hear the best dock when you're ~500 m out, with the phone locked | iPhone (background location + speech) | "Ask Dock Finder" → "start a ride to school" (or "Start a ride with Dock Finder") |
| Arrival alert from a Shortcuts **Arrive** automation (older approach) | iPhone (*Find Dock Near Saved Place* → Speak Text) | none, automatic |
| Dock near any address, landmark or neighborhood | iPhone (Apple map search) | "Ask Dock Finder" → "near Union Square" |
| Is a station full, and where to go instead | iPhone | "Ask Dock Finder" → "Mercer and Bleecker" |
| Citywide totals | iPhone | "Ask Dock Finder" → "how many bikes are out?" |
| Set a usual or backup dock, save a place | iPhone (in the app, the *Set Usual Dock* Shortcuts action, or by voice) | "Ask Dock Finder" → "my school dock is Mercer and Bleecker" / "save this spot as gym" |
| Cycling directions | Apple Maps / Google Maps links in the app | none |
| Anything else, in your own words | iPhone first (phrase rules, saved place and station names, then Apple Intelligence where available), **n8n backend** only when none of those understands the request or can find the place/station | "Ask Dock Finder", then say it |

Dock rules match the n8n workflow: a station counts only if it's installed, accepting returns, has **at least 2** open docks, and reported in the last hour. Destination searches stay within **1.2 km**. Station names are spoken the way New Yorkers say them ("W 15 St & 6 Ave" → "West 15th and 6th").

Every answer is one sentence. Siri speaks it, the app shows it, and Shortcuts receives it as text (so automations can pipe it into **Speak Text**).

## Layout

| Path | Purpose |
| --- | --- |
| `biker-app/App/DockFinderApp.swift` | Entry point; shows onboarding or home |
| `biker-app/Views/` | Home (with the ride card), Start Ride, saved places (add, edit, reorder, usual/backup dock pickers), dock near a place, station check, citywide, Ask, Siri instructions, onboarding |
| `biker-app/Intents/` | App Intents (`FindDockIntent.swift`), Siri phrases (`DockFinderShortcutsProvider`), saved place and station entities |
| `biker-app/Services/DockFinderService.swift` | Every on-device feature, shared by Siri and the UI |
| `biker-app/Models/StationNetwork.swift` | Joined station snapshot and the dock rules |
| `biker-app/Services/Speech.swift` | Spoken sentences and station-name rewriting (port of n8n's `make-it-speakable`) |
| `biker-app/Services/StationNameMatcher.swift` | Fuzzy matching of spoken station names |
| `biker-app/Services/PlaceSearch.swift` | Apple map search, limited to the Citi Bike service area |
| `biker-app/Services/RequestParsing.swift` | Free-form request understanding: phrase rules, then Apple's on-device model |
| `biker-app/Services/AssistantRouter.swift` | Decides between on-device answers and the backend |
| `biker-app/Services/AssistantBackend.swift` | n8n Siri webhook client |
| `biker-app/Models/Ride.swift`, `biker-app/Services/RideTracker.swift` | Rides: the arrival rules, and background tracking (live location + a geofence) |
| `biker-app/Services/Announcer.swift` | Speaks the arrival answer (ducking other audio) and posts it as a notification |
| `biker-app/State/` | Saved places (`UserDefaults`, on this device only) and onboarding state. The active ride is saved too, so tracking survives a relaunch |
| `Config/` | Build settings; your personal `Local.xcconfig` lives here (gitignored) |
| `DockFinderTests/` | Swift Testing unit tests |

## Building

- Xcode 26.6, iOS 26.5 deployment target.
- Personal settings live in `Config/Local.xcconfig`, which is gitignored. Create it once:

  ```bash
  cp ios/Config/Local.example.xcconfig ios/Config/Local.xcconfig
  ```

  Then fill in:
  - `DEVELOPMENT_TEAM`: your team ID (Xcode → Settings → Accounts → your Apple ID → the team shows its ID).
  - `DOCKFINDER_BUNDLE_ID`: something unique to you, e.g. `com.yourname.dockfinder`.
  - `DOCKFINDER_BACKEND_HOST` (optional): the group's n8n host, e.g. `yourname.app.n8n.cloud`. Ask a teammate. Leave it empty and the app never contacts a server; anything it can't answer on device gets a short help message instead.
- **A Development Team is required, even in the Simulator.** Without a Team ID, iOS's App Intents daemon (`linkd`) rejects the app with "Unable to get teamId … Rejecting invalid client due to requiresValidBundle". The intents still *appear* in Shortcuts but fail with "Unable to run App Shortcut".

```bash
xcodebuild -project biker-app.xcodeproj -scheme biker-app -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

To also run the opt-in test against the live Citi Bike feeds:

```bash
TEST_RUNNER_DOCKFINDER_LIVE_TESTS=1 xcodebuild -project biker-app.xcodeproj -scheme biker-app -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Rides

> "Hey Siri, ask Dock Finder" → "start a ride to school" → *"Got it. I'll tell you where to dock when you're about 0.3 miles from school."* → … → *"Your usual dock is full. Go to Washington and Greene, 8 docks, 350 feet from school."*

- The destination can be a saved place (uses its usual and backup docks and its own alert distance) or anywhere Apple Maps finds.
- While a ride is active, the app tracks location in the background, the way navigation apps do, and also sets a geofence around the destination. If iOS closes the app mid-ride, the geofence relaunches it on arrival.
- At the alert distance it **speaks** the best dock (lowering music or Maps while it talks) and posts the same sentence as a **notification**. With AirPods and *Announce Notifications* on, Siri reads the notification too.
- It fires once, then the ride ends. A ride that never arrives stops after **60 minutes**. Say "end my ride" to stop early, or tap **End Ride** in the app.
- If you start a ride while already within the alert distance, it answers right away.
- **Needs Always location access** to work with the phone locked. The app asks when you start a ride from its screen; if it was denied, the ride card links to Settings. With only *While Using*, Siri's answer says so.

## Saved places

- **Names and nicknames.** Give a place other names ("School" → "Stern", "class"); Siri and the Ask screen recognize all of them, plus "my school", "the school", "my school dock", and one-letter typos. Two places can't share a name or nickname.
- **Usual and backup docks.** The usual dock is checked first, then the backup, then the nearest other station with room. If a picked station disappears from Citi Bike's list, the place shows a warning.
- **Alert distance** per place for rides: 0.2, 0.3, 0.5 or 0.7 miles (300 m to 1.2 km).
- **Edit anything** (name, nicknames, location, alert distance), set a location with **Use My Current Location**, reorder or delete places, and get a warning if a place has no Citi Bike station within 1.2 km.
- **By voice:** "my school dock is Mercer and Bleecker", "save this spot as gym".
- **Storage is defensive:** places saved by older versions still load, one damaged entry doesn't wipe the list, and unreadable data is kept aside instead of being overwritten.

## Arrival alerts with a Shortcuts automation (older approach)

Rides replace this for most people. It still works if you'd rather have an alert every time you arrive, ride or not.

1. In Dock Finder, **Add a Place** (e.g. School), then open it and pick its **Usual Dock**.
2. In the Shortcuts app: **Automation** tab → **+** → **Arrive** → choose the location and drag the circle to about 500 m → **Run Immediately** → **Next** → **New Blank Automation**.
3. **Add Action** → search **Dock Finder** → **Find Dock Near Saved Place** → set Place to School.
4. **Add Action** → **Speak Text**, with the input set to the previous action's result. Turn on **Wait Until Finished**.
5. Tap **▶︎** to test. You should hear something like "Your usual dock has 25 docks open."

No server is involved, so it answers in about a second.

## Testing the developer preview on your own iPhone

There's no TestFlight build yet, so each tester installs the app on their own iPhone from Xcode. A free Apple ID is enough.

### What you need

- A Mac with **Xcode 26.6 or newer**, signed in to your Apple ID (Xcode → Settings → Accounts → **+** → Apple ID).
- An iPhone on **iOS 26.5 or newer** and a USB cable. Wi-Fi works after the first install.

### One-time setup

1. **Get the code.**
   ```bash
   git clone https://github.com/HLNave/citibike-smart-dock-assistant.git
   ```
   Then open `ios/biker-app.xcodeproj` in Xcode.
2. **Connect your iPhone**, unlock it, and tap **Trust This Computer**.
3. **Turn on Developer Mode** on the iPhone: Settings → Privacy & Security → **Developer Mode**. The phone restarts; confirm when asked. If the option isn't there, do step 5 first and it will appear.
4. **Set up signing** in `ios/Config/Local.xcconfig` (see [Building](#building)): copy `Local.example.xcconfig`, then set `DEVELOPMENT_TEAM` to your own team ID and `DOCKFINDER_BUNDLE_ID` to something unique to you, e.g. `com.yourname.dockfinder`. Bundle IDs are unique across all Apple accounts, so the default `spork.biker-app` only works for its owner. With a free Apple ID, your team is "*Your Name* (Personal Team)". After reopening the project, **Signing & Capabilities** should show that team with **Automatically manage signing** checked.
5. **Choose your iPhone as the run destination** in the device menu at the top of the Xcode window, not a simulator. With a free team, Xcode only registers your phone (and creates a provisioning profile) once the phone is selected here. If Signing & Capabilities showed "Your team has no devices" or "No profiles found", click **Try Again** now.
6. **Build and run** with **⌘R**.
7. **Trust your developer certificate.** The first launch is blocked with "Untrusted Developer". On the iPhone, go to Settings → General → **VPN & Device Management**, tap your Apple ID, then **Trust**. Press ⌘R again.

Optional: Window → Devices and Simulators → select your phone → **Connect via network**, so later installs don't need the cable.

### Things to know

- **Free-team installs expire after 7 days.** Run the app from Xcode again to reinstall. A paid Apple Developer Program membership lifts this and is needed for TestFlight.
- **Keep signing out of the project file.** Set your team and bundle ID in `Local.xcconfig`, not with the Team menu in Xcode. The menu writes them into `project.pbxproj`, which is shared. If that happens, run `git diff` before committing and leave those lines out.
- **Siri needs a Development Team.** Without one, Find Dock appears in Shortcuts but fails with "Unable to run App Shortcut" (see Building above).
- **Report results.** Work through the checklist below and post what you found (with screenshots of any errors) in the group chat or as a GitHub issue.

## Manual verification checklist (physical iPhone)

These can't be automated and **have not yet been verified on a device**. The Simulator runs have covered the in-app screens with live data:

- [ ] Fresh install → Welcome screen → button shows the location prompt → Siri instructions screen.
- [ ] "Dock Finder shortcuts" link opens Shortcuts and shows all six actions.
- [ ] "Hey Siri, ask Dock Finder" asks "Where are you headed, or which station?" **without opening the app** (`supportedModes = .background`), with the phone locked and headphones in. (Confirmed working on one iPhone 12 Pro; locked + headphones still to check.)
- [ ] Answering "school", "near Union Square", "Mercer and Bleecker", "near me" and "how many bikes are out" each gets the right answer.
- [ ] Saying "Hey Siri, ask Doc Finder" (or Siri showing "doc") still reaches the app.
- [ ] A question it can't understand is answered by the server (if `DOCKFINDER_BACKEND_HOST` is set).
- [ ] One-step phrases: "Hey Siri, find a dock with Dock Finder" and, after adding School, "Hey Siri, find a dock near school with Dock Finder". The second can take a minute to register after adding the place.
- [ ] "Ask Dock Finder" → "start a ride to school", lock the phone, ride: about 500 m out, the answer is spoken through headphones (music ducks) and shows as a notification. Then the ride card is gone.
- [ ] The Always location prompt appears when starting a ride from the app, and the ride card's notice goes away once it's allowed.
- [ ] If iOS closes the app mid-ride (after using lots of other apps), the geofence still alerts on arrival. Also try swiping the app away during a ride, to learn whether iOS relaunches a force-quit app for it.
- [ ] "Ask Dock Finder" → "end my ride" stops it; "my school dock is Mercer and Bleecker" and "save this spot as gym" update saved places.
- [ ] An Arrive automation running *Find Dock Near Saved Place* → Speak Text speaks the answer through headphones with the phone locked.
- [ ] Location permission never granted → Siri says to open Dock Finder.
- [ ] Location revoked in Settings → Siri reports permission denied, and the app shows the Settings notice.
- [ ] Airplane mode → "couldn't reach Citi Bike".
- [ ] Approximate location only → result includes the "location is approximate" caveat.

If the background location fix turns out to be unavailable to the intent on device, switch `supportedModes` to `[.background, .foreground(.dynamic)]` and call `continueInForeground` before retrying. In-process App Intents are expected to have When In Use access while running, but only a device test can confirm that.

## Reference shortcuts (analysis)

The three supplied `.shortcut` files are signed Apple Encrypted Archives. They were decoded with `aea decrypt -sign-pub` (using the key from the embedded signing certificate) followed by `aa extract`.

**Dock Finder.shortcut**: Ask for Input ("What do you need?") → Get Current Location → `POST https://YOUR-N8N-HOST/webhook/citibike-siri` with `{text, lat, lon, sessionId: "<name>"}` → Speak the response.

- The app's **Ask Dock Finder** intent replaces this shortcut ("Hey Siri, ask Dock Finder"; with the app installed, "run Dock Finder" opens the app instead). It answers on device when it can and sends the same `{text, lat, lon, sessionId}` body to the same webhook otherwise, with a random per-install session ID instead of a first name.

**School Automation.shortcut** + **CitiBike App Detection.shortcut**: a personal-automation pair.

- *App Detection* (presumably triggered when the Citi Bike app opens) writes the current ISO-8601 timestamp to `ride.txt`.
- *School Automation* (presumably a location trigger) reads `ride.txt`. If more than 60 minutes have passed, it exits. Otherwise it geocodes "44 W 4th Street", POSTs `{place: "school", destLat, destLon}` to `…/webhook/citibike-arrival`, speaks the response, and resets `ride.txt` to `2000-01-01`.
- The app's **Find Dock Near Saved Place** intent covers the same need on device (see [Arrival alerts](#arrival-alerts-replaces-the-n8n-arrival-webhook)). The ride-detection timestamp trick isn't reproduced; use a Time Range on the Arrive automation instead.
