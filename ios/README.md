# Dock Finder

A SwiftUI app that answers Citi Bike dock questions through Siri and its own screens. Everything that can run on the iPhone does. It reads Citi Bike's public GBFS feeds directly and uses Apple's map search for places. Only free-form questions the phone can't understand go to the group's n8n workflow.

> "Hey Siri, start a ride with Dock Finder."
> Siri: "Where are you heading?"
> "School."
> Siri: "Got it. I'll tell you where to dock when you're about 0.3 miles from School."
> *…as you get close:* "Your usual dock is full. Go to Washington and Greene, 8 docks, 350 feet from school."

## Using it with Siri

Two phrases cover what riders need:

- **"Hey Siri, start a ride with Dock Finder."** Siri asks **"Where are you heading?"** Answer with a saved place ("school", "my office" if you saved it), a landmark ("Union Square", "NYU Stern") or an address. Dock Finder starts a [ride](#rides) and tells you where to dock as you get close, even with the phone locked. (Also: "begin a ride…", "start riding…", "new ride with Dock Finder".)
- **"Hey Siri, find a dock with Dock Finder."** Answers straight away with the nearest station to you that has room. No follow-up question. (Also: "find me a dock", "find the nearest dock", "find an open dock", "nearest dock in Dock Finder".)

Why it's built this way: "where are you heading?" only makes sense when you're starting a ride, and nobody needs a dock *at* a place before they've ridden there. If you need one right now, it's near you.

The destination reaches the app as plain text, so Siri can't turn it into a Maps search. ("Dock" sounds like "doc", so a one-step "find a dock near school" can come out as a search for doctors.) The app treats a dictated "doc" as "dock", and "Doc Finder" is registered as an alternate app name (`INAlternativeAppNames` in `Config/Info.plist`). If you name a personal place that isn't saved ("home", "the office", "my gym"), Dock Finder asks you to add it instead of guessing a business with that name on the map.

Every answer that names a dock ends with **"Want me to direct you there?"**, and a new ride asks **"Want me to guide you to the dock when you're close?"** Say "yes" for spoken turn-by-turn directions (see [Directions to the dock](#directions-to-the-dock)).

More phrases:

- "Stop directions with Dock Finder" (also "cancel directions…", "stop guiding…")
- "Direct me with Dock Finder" (also "guide me to a dock…", "get directions…"): directions to the dock just mentioned, or the nearest one with room
- "End my ride with Dock Finder" (also "cancel my ride…"); also stops directions
- "Check my school dock with Dock Finder" (your usual dock's status right now; works with any saved place's name)
- "Check a station with Dock Finder" (also "is a station full in Dock Finder") → Siri asks which station
- "Citi Bike status in Dock Finder" (also "check Citi Bike citywide with Dock Finder") for citywide totals
- **"Ask Dock Finder"** (also "talk to Dock Finder") → "What do you need?" → anything in your own words: "is Mercer and Bleecker full?", "find a dock near Union Square", "how many bikes are out?", "start a ride to school", "end my ride", "my school dock is Court and State", "save this spot as gym". Requests it can't answer on the phone go to the n8n server if one is configured.

The [root README](../README.md#what-to-say-to-siri) has the complete phrase list and everything "Ask Dock Finder" understands. Keep it in sync when phrases change.

Only Find Dock has phrases starting with "find a dock". Siri matches phrases loosely, so a second "find a dock near …" phrase could win instead and ask a question, which turns the one-step request into a conversation.

> **Why not "run Dock Finder"?** Siri treats "run", "open", "launch" or "start" plus an app's name as "open the app", which beats the app's own phrases and needs the phone unlocked. "Start a ride with Dock Finder" works because it isn't just a verb plus the app name. If you still have the old MVP's **Dock Finder** shortcut in the Shortcuts app, delete it.

## What runs where

| Feature | Runs on | Siri phrase |
| --- | --- | --- |
| **Ride alert**: start a ride to a saved place or anywhere, hear the best dock when you're ~500 m out, with the phone locked | iPhone (background location + speech) | "Start a ride with Dock Finder" → "school" |
| **Saved-place arrival alert**: bike up to a saved place without starting a ride, hear the best dock at its alert distance | iPhone (geofences + motion activity + speech) | none, automatic |
| Nearest dock to you, right now | iPhone | "Find a dock with Dock Finder" |
| Your usual dock at a saved place, rerouting if it's full | iPhone | "Check my school dock with Dock Finder" |
| Dock near any address, landmark or neighborhood, right now | iPhone (Apple map search) | In the app (**Dock Near a Place**), or "Ask Dock Finder" → "find a dock near Union Square" |
| Is a station full, and where to go instead | iPhone | "Check a station with Dock Finder", or "Ask Dock Finder" → "is Mercer and Bleecker full?" |
| Citywide totals | iPhone | "Citi Bike status in Dock Finder", or "Ask Dock Finder" → "how many bikes are out?" |
| Set a usual or backup dock, save a place | iPhone (in the app, or by voice) | "Ask Dock Finder" → "my school dock is Mercer and Bleecker" / "save this spot as gym" |
| **Turn-by-turn directions to a dock**, spoken with the phone locked, with a Lock Screen / Dynamic Island Live Activity | iPhone (Apple cycling routes, background location, speech) | "yes" to "Want me to direct you there?", or "Direct me with Dock Finder" |
| Anything else, in your own words | iPhone first (phrase rules, saved place and station names, then Apple Intelligence where available), **n8n backend** only when none of those understands the request or can find the place/station | "Ask Dock Finder", then say it |

Dock rules match the n8n workflow: a station counts only if it's installed, accepting returns, has **at least 2** open docks, and reported in the last hour. Destination searches stay within **1.2 km**. Station names are spoken the way New Yorkers say them ("W 15 St & 6 Ave" → "West 15th and 6th").

Every answer is one sentence. Siri speaks it and the app shows it.

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
| `biker-app/Models/Guidance.swift` | Directions rules: the route, where the rider is along it, what to say when, and mid-ride dock checks |
| `biker-app/Services/GuidanceSession.swift` | Runs directions: Apple cycling routes, background location, spoken turns, re-routing, dock re-checks |
| `biker-app/Services/DockFinderLiveActivity.swift` | Starts, updates and ends the ride / directions Live Activity |
| `Shared/` | Code compiled into both the app and the widget extension (the Live Activity's data) |
| `DockFinderWidgets/` | Widget extension that draws the Live Activity on the Lock Screen and in the Dynamic Island |
| `biker-app/Models/PlaceArrival.swift`, `biker-app/Services/PlaceArrivalMonitor.swift` | Saved-place arrival alerts without a ride: geofences per place, the "only when biking" check, and the alert |
| `biker-app/State/` | Saved places (`UserDefaults`, on this device only) and onboarding state. The active ride is saved too, so tracking survives a relaunch |
| `Config/` | Build settings; your personal `Local.xcconfig` lives here (gitignored) |
| `Tools/make_app_icon.py` | Draws the app icon (light, dark and tinted) into `Assets.xcassets/AppIcon.appiconset`; rerun after changing it (needs Pillow) |
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

> "Hey Siri, start a ride with Dock Finder" → *"Where are you heading?"* → "school" → *"Got it. I'll tell you where to dock when you're about 0.3 miles from school."* → … → *"Your usual dock is full. Go to Washington and Greene, 8 docks, 350 feet from school."*

- The destination can be a saved place (uses its usual and backup docks and its own alert distance) or anywhere Apple Maps finds.
- While a ride is active, the app tracks location in the background, the way navigation apps do, and also sets a geofence around the destination. If iOS closes the app mid-ride, the geofence relaunches it on arrival.
- At the alert distance it **speaks** the best dock (lowering music or Maps while it talks) and posts the same sentence as a **notification**. With AirPods and *Announce Notifications* on, Siri reads the notification too.
- It fires once, then the ride ends. A ride that never arrives stops after **60 minutes**. Say "end my ride" to stop early, or tap **End Ride** in the app.
- If you start a ride while already within the alert distance, it answers right away.
- **Guidance to the dock:** Siri asks "Want me to guide you to the dock when you're close?" when the ride starts (the app has a **Guide me to the dock** switch instead). With "yes", the arrival alert is followed by [turn-by-turn directions](#directions-to-the-dock) to the dock it named. "Stop directions" before you arrive turns this off for the ride.
- A **Live Activity** shows "Riding to school" and the distance to go on the Lock Screen and in the Dynamic Island, and switches to the next turn once directions start.
- **Needs Always location access** to work with the phone locked. The app asks when you start a ride from its screen; if it was denied, the ride card links to Settings. With only *While Using*, Siri's answer says so.

## Directions to the dock

> "Hey Siri, find a dock with Dock Finder" → *"West 15th and 6th has 8 docks open, 300 feet away. Want me to direct you there?"* → "Yes" → Siri: *"Okay, directing you to West 15th and 6th."* → Dock Finder's voice: *"0.1 miles to West 15th and 6th. Head north on 6th Avenue."* → … → *"In 200 feet, turn left onto West 15th Street."* → *"Turn left onto West 15th Street."* → *"You've arrived at West 15th and 6th, 8 docks open."*

- **Where it starts:** "yes" to Siri's follow-up after any dock answer (Find Dock, Check Station, Find Dock Near Saved Place / Near a Place, Ask Dock Finder); "Direct me with Dock Finder" or "take me there" in Ask (the dock offered in the last 10 minutes, else the nearest with room); **Direct Me** under any dock answer in the app; or a ride's arrival when the rider asked to be guided.
- **Two voices, never at once:** Siri only confirms ("Okay, directing you to …"). Dock Finder's own voice gives every instruction, holding anything it would say until Siri should have finished (estimated from the length of Siri's sentence).
- **Starting direction:** Apple's first step is often just "Start on West 14th Street", or empty. The opening adds which way to go from the route's first 25 m: "Head east on West 14th Street", or "Head east, then in 300 feet, turn left onto 7th Avenue". North/south/east/west only, which matches Manhattan's grid (avenues north–south, streets east–west).
- **Route:** Apple's cycling directions (`MKDirections`, `.cycling`). Apple Maps instructions are rewritten to be spoken ("W 4th St" → "West 4th Street", "The destination is on your left" → "The dock is on your left").
- **When it speaks:** each turn about 150 m ahead ("In 500 feet, turn right onto Bleecker Street") and again about 35 m ahead ("Turn right onto Bleecker Street"); arrival within 30 m of the dock. Fixes worse than 65 m accuracy are ignored.
- **Off route:** two fixes in a row more than 45 m from the route → "Rerouting." and the new next turn (at most every 20 s).
- **Dock re-checks:** every 2 minutes and once more 400 m out. If the dock has filled up or closed, it says so and re-routes to the nearest station with room; if nothing nearby has room, it says that and keeps going.
- **Ends** at the dock, on "stop directions" / "end my ride" / **Stop Directions** in the app, or after 45 minutes.
- **Locked phone:** like rides, needs **Always** location access; with only *While Using*, it works while Dock Finder is open, and Siri's answer says how to fix it.
- **Live Activity:** next-turn arrow, instruction, distance, dock name and open docks on the Lock Screen and Dynamic Island. iOS only lets apps *start* one while on screen or running a Live Activity intent, so every intent that can start directions or a ride is a `LiveActivityIntent`.

## Saved places

- **Names and nicknames.** Give a place other names ("School" → "Stern", "class"); Siri and the Ask screen recognize all of them, plus "my school", "the school", "my school dock", and one-letter typos. Two places can't share a name or nickname.
- **Usual and backup docks.** The usual dock is checked first, then the backup, then the nearest other station with room. If a picked station disappears from Citi Bike's list, the place shows a warning.
- **Alert distance** per place for rides: 0.2, 0.3, 0.5 or 0.7 miles (300 m to 1.2 km).
- **Edit anything** (name, nicknames, location, alert distance), set a location with **Use My Current Location**, reorder or delete places, and get a warning if a place has no Citi Bike station within 1.2 km.
- **By voice:** "my school dock is Mercer and Bleecker", "save this spot as gym".
- **Storage is defensive:** places saved by older versions still load, one damaged entry doesn't wipe the list, and unreadable data is kept aside instead of being overwritten.
- **Arrival alerts without a ride** (on by default, **Alert Me When I Arrive** per place). iOS watches a geofence around each saved place at its alert distance (`CLMonitor`, so it costs almost no battery and relaunches the app if needed). On entering one, Dock Finder checks the motion coprocessor (`CMMotionActivityManager`): it alerts only if the latest confident activity in the last hour is cycling, or cycling started in the last 5 minutes. Then it speaks the dock answer and posts it as a notification, and offers "Hey Siri, direct me with Dock Finder". At most once an hour per place, never during a ride or directions. Needs Always location; without Motion & Fitness access, arrivals aren't filtered.
- **They survive reinstalling.** A copy is kept in the iPhone's keychain (`State/PlacesBackup.swift`), which iOS keeps when an app is deleted, and is restored on a fresh install. It only works with the same bundle ID and signing team, and it's long-standing iOS behavior rather than a documented guarantee. Nothing leaves the phone; iCloud sync would need a paid developer account.

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

- **Installing a new build: don't delete the app first.** Press ⌘R and it installs over the old one. iOS forgets the "Trust" from step 7 once no apps from your team are left on the phone, so deleting means trusting again (and granting location again).
- **Free-team installs expire after 7 days.** Press ⌘R before then to refresh it. Saved places come back even if you deleted the app; location permission has to be granted again. A paid Apple Developer Program membership lifts this and is needed for TestFlight.
- **Keep signing out of the project file.** Set your team and bundle ID in `Local.xcconfig`, not with the Team menu in Xcode. The menu writes them into `project.pbxproj`, which is shared. If that happens, run `git diff` before committing and leave those lines out.
- **Siri needs a Development Team.** Without one, Find Dock appears in Shortcuts but fails with "Unable to run App Shortcut" (see Building above).
- **If Siri runs the wrong action or keeps re-asking a question** after installing a new build, delete Dock Finder from the phone and install it again. iOS caches which phrase runs which action. For developers: never reorder or remove entries in `DockFinderShortcutsProvider` (append only), and bump `CURRENT_PROJECT_VERSION` in `Config/DockFinder.xcconfig` whenever the phrases change. `SiriPhraseTests` fails if the order changes.
- **Report results.** Work through the checklist below and post what you found (with screenshots of any errors) in the group chat or as a GitHub issue.

## Manual verification checklist (physical iPhone)

These can't be automated and **have not yet been verified on a device**. The Simulator runs have covered the in-app screens with live data:

- [ ] Fresh install → Welcome screen → button shows the While Using location prompt, then straight away "Change to Always Allow" → Siri instructions screen.
- [ ] Add a place, delete the app, reinstall from Xcode: the place (with its usual dock) is back.
- [ ] Onboarding asks for Motion & Fitness after the two location prompts.
- [ ] Without starting a ride, bike toward a saved place with the phone locked: about the alert distance out, the dock answer is spoken and shows as a notification. "Hey Siri, direct me with Dock Finder" then starts directions to that dock.
- [ ] Walking (or arriving by subway) into the same place doesn't alert. A second arrival within the hour doesn't alert. Turning **Alert Me When I Arrive** off stops it.
- [ ] With the app swiped away, biking up to a saved place still alerts (iOS relaunches it for the geofence).
- [ ] On the "Use Dock Finder with Siri" screen, the Dock Finder shortcuts button (Apple's list of the app's Siri phrases) shows nine entries.
- [ ] "Hey Siri, start a ride with Dock Finder" asks "Where are you heading?" **without opening the app**, with the phone locked and headphones in. Answering "school", "Union Square" and "44 West 4th Street" each starts a ride; "home" (not saved) asks you to add it.
- [ ] "Hey Siri, ask Dock Finder" asks "What do you need?" (confirmed reachable on an iPhone 12 Pro), and "is Mercer and Bleecker full?" / "how many bikes are out?" get the right answer.
- [ ] Saying "Doc Finder" (or Siri showing "doc") still reaches the app.
- [ ] A question it can't understand is answered by the server (if `DOCKFINDER_BACKEND_HOST` is set).
- [ ] "Hey Siri, find a dock with Dock Finder" (and "find me a dock…", "find the nearest dock…") answers with the nearest dock **without asking anything first**, then asks "Want me to direct you there?"
- [ ] With the phone locked and headphones in, "yes" to that question starts directions **without unlocking**: Siri says "Okay, directing you to …", then Dock Finder's voice gives the first instruction (with a direction, e.g. "Head east on…") without the two overlapping. "No" just ends with "Okay."
- [ ] Riding with directions, phone locked: each turn is announced ahead and at the corner, music ducks, and arrival is announced at the dock. Taking a wrong turn gives "Rerouting." within a few seconds.
- [ ] The Lock Screen and Dynamic Island show the next turn, the distance and the dock's open docks, and update as you ride; the activity ends a couple of minutes after arrival.
- [ ] "Hey Siri, stop directions with Dock Finder" stops directions and removes the Live Activity. "Hey Siri, direct me with Dock Finder" after saying "no" starts directions to the same dock.
- [ ] "Start a ride with Dock Finder" → "school" asks "Want me to guide you to the dock when you're close?" With "yes", the arrival alert is followed by directions to the dock it named.
- [ ] A ride shows a "Riding to school" Live Activity with the distance to go.
- [ ] **Direct Me** under an answer in the app starts directions; the directions card shows the next turn and **Stop Directions** works.
- [ ] Cycling routes: if Xcode reports `.cycling` as unavailable in `GuidanceSession.swift`, switch it to `.walking` and note it here.
- [ ] After adding School, "Hey Siri, check my school dock with Dock Finder" works. It can take a minute to register after adding the place.
- [ ] "Start a ride with Dock Finder" → "school", lock the phone, ride: about 500 m out, the answer is spoken through headphones (music ducks) and shows as a notification. Then the ride card is gone.
- [ ] The Always location prompt appears when starting a ride from the app, and the ride card's notice goes away once it's allowed.
- [ ] If iOS closes the app mid-ride (after using lots of other apps), the geofence still alerts on arrival. Also try swiping the app away during a ride, to learn whether iOS relaunches a force-quit app for it.
- [ ] "Ask Dock Finder" → "end my ride" stops it; "my school dock is Mercer and Bleecker" and "save this spot as gym" update saved places.
- [ ] Location permission never granted → Siri says to open Dock Finder.
- [ ] Location revoked in Settings → Siri reports permission denied, and the app shows the Settings notice.
- [ ] Airplane mode → "couldn't reach Citi Bike".
- [ ] Approximate location only → result includes the "location is approximate" caveat.

If the background location fix turns out to be unavailable to the intent on device, switch `supportedModes` to `[.background, .foreground(.dynamic)]` and call `continueInForeground` before retrying. In-process App Intents are expected to have When In Use access while running, but only a device test can confirm that.
