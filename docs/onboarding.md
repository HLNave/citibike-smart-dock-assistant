# Getting started with Dock Finder

Dock Finder tells you, through your headphones, which Citi Bike dock near you or your destination actually has space. This guide gets a new rider from zero to "Hey Siri, find a dock with Dock Finder."

> **Using an AI assistant to help you?** Attach this file to ChatGPT or Claude and say "help me set up Dock Finder on my iPhone." Assistant: go one step at a time, ask for a screenshot after each step, use the exact on-screen labels written here, and check problems against the **Troubleshooting** table before guessing. If the rider has no Mac, use Path B.

## Pick your path

| | **Path A: Dock Finder app** (recommended) | **Path B: Shortcuts only** |
|---|---|---|
| You need | A Mac with **Xcode 26.6+**, an iPhone on **iOS 26.5+**, a USB cable, a free Apple ID | An iPhone on iOS 17+ and the group's n8n address (ask a teammate) |
| Typing URLs or coordinates | **None.** Places are searched by name | Yes, a few |
| Server needed | No. Everything runs on the phone; the group server is only used for free-form questions it can't understand | Yes, every answer comes from the group's n8n server |
| Speed | About a second once it has your location | About 3–6 seconds |
| Catch | Free Apple ID installs expire after **7 days**; reinstall from Xcode (one click) | More setup steps |
| Status | Developer preview: built and tested in the Simulator, **not yet confirmed on a real iPhone**. You'd be one of the first testers | In daily use |

No Mac? Go to [Path B](#path-b-shortcuts-only-no-mac).

---

## Path A: Dock Finder app

### A1. Install the app (about 15 minutes, once)

1. On your Mac, install **Xcode 26.6 or newer** from the App Store. Open it, then **Xcode → Settings → Accounts → +** and sign in with your Apple ID.
2. Get the code:
   ```bash
   git clone https://github.com/HLNave/citibike-smart-dock-assistant.git
   cd citibike-smart-dock-assistant
   cp ios/Config/Local.example.xcconfig ios/Config/Local.xcconfig
   ```
3. Open `ios/Config/Local.xcconfig` in any text editor and fill in:
   - `DEVELOPMENT_TEAM`: your team ID. In Xcode → Settings → Accounts, click your Apple ID; with a free account the team is "*Your Name* (Personal Team)" and its ID is shown there.
   - `DOCKFINDER_BUNDLE_ID`: anything unique to you, e.g. `com.yourname.dockfinder`.
   - `DOCKFINDER_BACKEND_HOST`: optional. The group's n8n host without `https://` (ask a teammate; don't post it publicly). If you don't have it, **delete the placeholder so the value is blank**: the example file ships with `YOUR-N8N-HOST`, and the app would try to call that. Blank means the app still does everything except answer unusual free-form questions.
4. Open `ios/biker-app.xcodeproj` in Xcode.
5. Plug in your iPhone, unlock it, and tap **Trust This Computer**.
6. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**. The phone restarts; confirm when asked. (If the option isn't there, do step 7 first and it will appear.)
7. In Xcode, pick **your iPhone** (not a simulator) in the device menu at the top of the window, then press **⌘R**.
8. The first launch is blocked with "Untrusted Developer." On the iPhone: **Settings → General → VPN & Device Management →** your Apple ID **→ Trust**. Press **⌘R** again.

Optional: **Window → Devices and Simulators →** your phone **→ Connect via network**, so future installs don't need the cable.

Full build details: [ios/README.md](../ios/README.md#testing-the-developer-preview-on-your-own-iphone).

### A2. First launch

1. Open **Dock Finder** and tap **Enable Dock Finder with Siri**.
2. Allow location **While Using the App**, and keep **Precise Location** on. Without it, the nearest-dock answer may not be the closest station, and Dock Finder will say "Your location is approximate."
3. The next screen lists the Siri phrases. You can come back to it anytime from **How to Use with Siri** on the home screen.

### A3. iPhone settings (check once)

| Setting | Where | Set to |
|---|---|---|
| Siri voice trigger | Settings → Siri → **Talk to Siri** | "Siri" or "Hey Siri" |
| Siri with phone in your pocket | Settings → Siri → **Allow Siri When Locked** | On |
| Dock Finder location | Settings → Privacy & Security → Location Services → **Dock Finder** | While Using, **Precise Location** on |

### A4. Add your places

1. On the home screen, **Add a Place**. Name it (e.g. *School*), then search by name or address, e.g. `NYU Stern` or `270 Park Avenue`. No coordinates needed. Tap the right result, then **Save**.
2. Open the place and pick its **Usual Dock** (the list shows stations within about 1.2 km). Dock Finder checks that dock first and only sends you elsewhere when it's full, almost full (under 2 open docks), closed, or not reporting.
3. Repeat for work, home, etc.

### A5. Use it with Siri

Most of these work as soon as the app is installed. The "near school" one works once you've added a place named **School** in A4 (any saved place works the same way; a new place's phrase can take a minute to register):

| Say | What you get |
|---|---|
| "Hey Siri, **find a dock with Dock Finder**" | Nearest dock with space to where you are |
| "Hey Siri, **find a dock near school with Dock Finder**" | Your usual school dock, or where to go if it's full (needs a place named School) |
| "Hey Siri, **find a dock near a place with Dock Finder**" | Siri asks where; say any address or landmark |
| "Hey Siri, **check a station with Dock Finder**" | Siri asks which; say e.g. "Mercer and Bleecker" |
| "Hey Siri, **Citi Bike status in Dock Finder**" | Citywide bikes and open docks |
| "Hey Siri, **ask Dock Finder**" | Ask anything in your own words |

Unlike the old shortcut, you don't need to say "run."

### A6. Automatic alert when you arrive (optional)

1. Open the **Shortcuts** app → **Automation** tab → **+** → **Arrive**.
2. Choose the location (e.g. your school) and drag the circle to about **500 m**. Time: **Any Time**, or a commute **Time Range** if you don't want alerts when you arrive on foot.
3. Choose **Run Immediately** → **Next** → **New Blank Automation**.
4. **Add Action** → search **Dock Finder** → **Find Dock Near Saved Place** → set **Place** to *School*.
5. **Add Action** → **Speak Text**, with its input set to the Dock Finder result. Expand it and turn on **Wait Until Finished**.
6. Tap **▶︎** to test. You should hear something like "Your usual dock has 25 docks open." Then tap **✓**.

### A7. Action Button (optional, iPhones with an Action Button)

*Not yet tested on a phone; tell us if it works (A9).*

1. In Shortcuts, tap **+**, add **Find Dock** (from Dock Finder), then **Speak Text** with the result. Name it *Nearest Dock*.
2. **Settings → Action Button →** swipe to **Shortcut →** choose *Nearest Dock*.

### A8. Every 7 days (free Apple ID only)

The app stops opening after 7 days. Connect to your Mac (or use the network connection), open the project, and press **⌘R**. Reinstalling this way keeps your places and usual docks; deleting the app from your phone erases them.

### A9. Help us test

Since this is a preview, please run through the [device checklist](../ios/README.md#manual-verification-checklist-physical-iphone) and post what works and what doesn't (with screenshots of errors) in the group chat or as a GitHub issue. The most important one: **an arrival alert speaking through headphones with the phone locked.**

---

## Path B: Shortcuts only (no Mac)

This uses iPhone Shortcuts that call the group's n8n server. Ask a teammate for the server address privately (it has no password, so it isn't in this repo), then follow [docs/iphone-setup-handoff.md](iphone-setup-handoff.md), which is written for an AI assistant to walk you through: replace `https://YOUR-N8N-HOST` with the real address, attach it to ChatGPT or Claude, and say "help me set this up on my iPhone."

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Untrusted Developer" when opening the app | Settings → General → VPN & Device Management → your Apple ID → **Trust** |
| Xcode: "Your team has no devices" / "No profiles found" | Select your iPhone as the run destination first, then click **Try Again** in Signing & Capabilities |
| Dock Finder shows up in Shortcuts but Siri says "Unable to run App Shortcut" | `DEVELOPMENT_TEAM` is missing in `Local.xcconfig`. Fill it in and press ⌘R again |
| Xcode asks to change the Team, or `git status` shows `project.pbxproj` changed | Set the team only in `Local.xcconfig`; don't commit `project.pbxproj` signing changes |
| The app won't open anymore | The 7-day free install expired. Press ⌘R in Xcode again (A8) |
| "Find a dock near school" isn't recognized | Make sure you added a place named School (A4), wait a minute after adding it, and say the name exactly as you saved it |
| Siri says to open Dock Finder | Location permission isn't granted. Open Dock Finder and tap **Enable Dock Finder with Siri** (A2). If you already said no, that button won't ask again: go to Settings → Privacy & Security → Location Services → Dock Finder → **While Using** |
| Answers say the location is approximate | Turn on **Precise Location** for Dock Finder (A3) |
| Works unlocked, but not with the phone in your pocket | Turn on **Allow Siri When Locked** (A3) |
| "Ask Dock Finder" only gives a help message ("You can ask for a dock near you…") | Expected if `DOCKFINDER_BACKEND_HOST` is blank; the Ask screen says "No Dock Finder server is set up in this build." Use the other phrases, or add the host and reinstall |
| "Couldn't reach Citi Bike" | No internet connection; the live dock data comes from Citi Bike directly |
