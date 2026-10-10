# Getting started with Dock Finder

Dock Finder tells you, through your headphones, which Citi Bike dock near you or your destination actually has space. Setup takes about 5 minutes: you add a few shortcuts a teammate sends you, answer a couple of questions, and make one automation per place. No URLs, no coordinates.

> **Using an AI assistant to help you?** Attach this file to ChatGPT or Claude and say "help me set up Dock Finder on my iPhone." Assistant: go one step at a time, ask for a screenshot after each step, use the exact on-screen labels written here, and check problems against **Troubleshooting** before guessing.

## What you'll get

| Shortcut | How you use it | What you hear |
|---|---|---|
| **Dock Finder** | "Hey Siri, **run Dock Finder**", then ask anything | "Mercer and Bleecker has 29 docks open." |
| **Nearest Dock** | One press of the Action Button (or tap it) | "West 15th and 6th has 53 docks open, right there." |
| **Dock Arrival - School / Work / Home** | Runs by itself when you get within ~500 m | "your usual dock is full. go to Washington and Greene, 8 docks, 100 meters from school." |

## 1. Check your iPhone settings (once)

You need iOS 17 or newer (Settings → General → About).

| Setting | Where | Set to |
|---|---|---|
| Siri voice trigger | Settings → Siri → **Talk to Siri** | "Siri" or "Hey Siri" |
| Siri with the phone in your pocket | Settings → Siri → **Allow Siri When Locked** | On |
| Location | Settings → Privacy & Security → **Location Services** | On |
| Shortcuts location | Same screen → **Shortcuts** | **While Using the App**, with **Precise Location** on |

## 2. Add the shortcuts

A teammate sends you the shortcut files (or iCloud links). For each one:

1. Tap the file or link. It opens in the Shortcuts app.
2. Tap **Add Shortcut** (or **Set Up Shortcut**).
3. Answer its questions:
   - **Dock Finder** asks for your **first name**. It keeps your conversation separate from everyone else's.
   - **Dock Arrival** asks for the place's **address or name**: `44 W 4th St`, `NYU Stern` and `JPMC HQ` all work, and you don't need the city. It also asks for your **usual dock** there: just its two cross streets, e.g. `Mercer and Bleecker`. Leave that blank and it finds the closest dock with space.
   - **Nearest Dock** asks nothing.

Only add the Dock Arrival ones you need (School, Work, Home).

## 3. Allow access (once, before riding)

Open the **Shortcuts** app and tap **Nearest Dock**, then **Dock Finder** (answer "find me a dock near me"). iOS asks to use your location and to connect to the group's server. Choose **Always Allow** each time. These prompts need a tap, which you can't do mid-ride, so get them out of the way now.

## 4. Make an arrival automation for each place

1. Shortcuts app → **Automation** tab → **+** → **Arrive**.
2. **Choose** the location: search the same address, then drag the circle to about **500 m** (1.5–2 minutes before you get there on a bike).
3. Time: **Any Time**, or a commute **Time Range** if you don't want alerts when you arrive on foot or by subway.
4. Select **Run Immediately** (turn off **Notify When Run** if you see it), then **Next**.
5. Pick **Dock Arrival - School** from your shortcuts list. If you only see "New Blank Automation", tap it, **Add Action** → **Run Shortcut** → choose **Dock Arrival - School**.
6. Tap **Done**.

Repeat for Work and Home.

## 5. Action Button (optional)

Settings → **Action Button** → swipe to **Shortcut** → choose **Nearest Dock**.

## 6. Try it

- With AirPods in and the phone locked: "Hey Siri, **run Dock Finder**", then "find me a dock near me".
- Things you can ask: "is Mercer and Bleecker full?", "find me a dock near Union Square", "how many bikes are out?", "my school dock is Mercer and Bleecker".
- Open **Dock Arrival - School** in the Shortcuts app and tap **▶︎**. The first time, it tells you where it thinks your school is ("school is NYU Stern School of Business, 44 West 4th Street, Manhattan."), then the dock. If that place is wrong, fix the address (see Troubleshooting).

Always say "**run** Dock Finder". Without "run", Siri may treat it as a search or a message.

## Troubleshooting

| Problem | Fix |
|---|---|
| Siri does something else (searches Maps, texts someone) | Say "**run** Dock Finder" |
| It works unlocked but not in your pocket | Turn on **Allow Siri When Locked** (step 1) |
| "Near me" picks a station far away | Turn on **Precise Location** for Shortcuts (step 1) |
| A popup asks before the arrival alert runs | Edit the automation and choose **Run Immediately** |
| The first test says the wrong place ("school is …") | Open the Dock Arrival shortcut and change the address text at the top to a street address, e.g. `44 W 4th St`. Run ▶︎ again; it confirms the new place |
| "couldn't find … in new york city" | Same fix: use a street address with the number |
| "Your usual dock…" never comes up | The cross streets didn't match a station near that place. Check the dock's name in the Citi Bike app and use its two streets |
| A shortcut asks for permission mid-ride | Run it once from the Shortcuts app and choose **Always Allow** (step 3) |
| "The network connection was lost" | Try again. If it keeps happening, delete that shortcut and add it again from the file |
| Nothing happens and there's no error | Tell the group. Whoever runs the server can check if your request arrived |

---

## For whoever shares the shortcuts

What each shortcut does, step by step, is in [shortcuts.md](shortcuts.md). It updates itself on every push.

The shortcut files contain the group's n8n address, and the webhooks have no password. That's why they aren't in the repo. Build them from the latest code before sending:

```bash
git pull
python3 shortcuts/build_shortcuts.py --host YOUR-N8N-HOST
```

This writes signed files to `shortcuts/dist/` (gitignored), reading the webhook paths from `n8n/citibike-smart-dock-assistant.workflow.json`. That way the shortcuts always match the current backend. Rebuild and re-send whenever the backend changes. Riders delete the old shortcut and add the new one.

To share them:
- **Files:** AirDrop or text the `.shortcut` files. Opening one on an iPhone starts the import with its questions.
- **iCloud links (optional):** add a shortcut to your own phone, open it, tap **Share → Copy iCloud Link**, then text the link. Check once that a link opened on another phone still asks the setup questions before relying on it.

## Native app (developer preview, for testers with a Mac)

Dustin is building a native **Dock Finder** app (`ios/`) that runs the dock logic on the phone and saves places by name. It isn't on the App Store or TestFlight yet. Installing it needs a Mac with Xcode, and free installs expire every 7 days. If you want to help test it, follow [ios/README.md](../ios/README.md#testing-the-developer-preview-on-your-own-iphone). With the app installed, the Siri phrase changes to "Hey Siri, **ask** Dock Finder" (see that README for current phrases).
