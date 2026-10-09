# Citi Bike Smart Dock Assistant: iPhone setup handoff

> **Before sharing this file:** replace every `https://YOUR-N8N-HOST` with your own n8n address (e.g. `https://yourname.app.n8n.cloud`). The webhooks have no password, so only share the filled-in copy with people you trust.

> **Have the native iOS app installed?** You don't need these Shortcuts; see `ios/README.md`. If you made the "Dock Finder" shortcut below, delete or rename it, or "Hey Siri, run Dock Finder" may run it instead of the app.

## Read this first (instructions for the AI assistant)

You are helping a member of our group set up the Citi Bike Smart Dock Assistant on **their own iPhone**. The backend (an n8n workflow) is **already built and running**; do not build, host, or change anything server-side. The user only needs to create iPhone Shortcuts that call it.

How to help:
- Go **one step at a time**. After each step, ask the user to send a screenshot of the Shortcuts screen and check it against this document before moving on.
- Use the **exact** URLs, field names and settings below. Field names are case-sensitive (`destLat`, not `destlat`).
- Check every screenshot against the **Known pitfalls** section; each of those mistakes actually happened during our own setup.
- The user may not be technical. Use the iPhone's on-screen labels (e.g. "Get Contents of URL", "Add new field"), not developer jargon.
- Assume iOS 17 or newer. If the user is on an older iOS, tell them location automations will need a tap to confirm each time.

## What the user is setting up

Two things, both hands-free with AirPods/headphones:

1. **Arrival automations** (one per regular destination: school, work, home). When the user gets within ~500 m of that place, the phone automatically asks the backend for live dock availability and **speaks one sentence**, e.g. "your usual dock has 25 docks open." or "your usual dock is full. go to Washington and Greene, 8 docks, 100 meters from school."
2. **"Dock Finder" Siri shortcut**. The user says "Hey Siri, **run Dock Finder**", Siri asks "What do you need?", the user answers out loud (e.g. "find me a dock near me", "is Mercer and Bleecker full?", "find me a dock near Union Square"), and the phone speaks the answer.

The phone does the speech recognition and the text-to-speech itself (free, works through headphones, lowers Google Maps' voice while it talks). The backend returns **plain text, one sentence**.

## Backend endpoints (already live, shared by the group)

Both are `POST` with a JSON body and return plain text.

| Use | URL |
|---|---|
| Arrival automations | `https://YOUR-N8N-HOST/webhook/citibike-arrival` |
| Dock Finder (Siri) | `https://YOUR-N8N-HOST/webhook/citibike-siri` |

Arrival body fields:

| Key | Type in Shortcuts | Value |
|---|---|---|
| `place` | Text | a short name: `school`, `work`, `home` |
| `destLat` | Text | the place's latitude, e.g. `40.7289502` |
| `destLon` | Text | the place's longitude, e.g. `-73.9960792` (NYC longitudes are **negative**; keep the minus sign) |
| `usualDock` | Text | optional: the user's usual Citi Bike station name at that place, e.g. `Mercer St & Bleecker St` |

Siri body fields:

| Key | Type in Shortcuts | Value |
|---|---|---|
| `text` | Text | the **Provided Input** variable from "Ask for Input" |
| `lat` | Text | **Current Location** variable, tapped and set to **Latitude** |
| `lon` | Text | **Current Location** variable, tapped and set to **Longitude** |
| `sessionId` | Text | the user's first name, e.g. `maya`. It must be different for each person; it keeps their conversation memory separate |

## Part 0: iPhone settings to check first

Walk the user through these before building anything; ask for a screenshot of each screen if unsure.

| Setting | Where | Set to | Why |
|---|---|---|---|
| iOS version | Settings → General → About | iOS 17 or newer | Older iOS makes location automations ask for a tap every time |
| Siri voice trigger | Settings → Siri (older iOS: Siri & Search) → **Talk to Siri** / **Listen for** | "Siri" or "Hey Siri" | So "Hey Siri, run Dock Finder" works hands-free |
| Siri when locked | Settings → Siri → **Allow Siri When Locked** | On | The phone is locked in your pocket while riding |
| Location Services | Settings → Privacy & Security → **Location Services** | On | Both arrival automations and Dock Finder need location |
| Shortcuts location access | Same screen → scroll to **Shortcuts** | **While Using the App**, with **Precise Location** on | Without Precise Location, "near me" can be off by hundreds of meters |
| Low Power Mode | Settings → Battery | Off when you can | It can delay location-based automations |

AirPods/headphones need no special setting: Speak Text plays through whatever audio output is connected.

## Part 1: Arrival automation (repeat for each place)

1. Open **Shortcuts**, go to the **Automation** tab, tap **+**, then choose **Arrive**.
2. Choose the location (e.g. the school building). Drag the circle to roughly **500 m** (about 1.5–2 minutes before arrival on a bike).
3. Time: **Any Time** is fine. (Optional: a **Time Range** for commute hours cuts down announcements when arriving on foot or by subway. iOS can't tell that you're biking.)
4. Select **Run Immediately**. If a **Notify When Run** toggle exists, turn it off; if it doesn't exist on this iOS version, that's fine.
5. Tap **Next**, then **New Blank Automation**.
6. **Add Action**, search **Get Contents of URL**, and add it. (Not "Open URLs"!)
7. Tap the URL and paste the **arrival** URL from the table above.
8. Tap the **▸ / ⌄** on the action to show more: set **Method = POST** and **Request Body = JSON**.
9. **Add new field**, choose **Text**, then add `place`, `destLat`, `destLon` and optionally `usualDock` (see the table).
   - To get coordinates: in Google Maps, **long-press** the building; the coordinates appear at the top (latitude first, then longitude).
10. **Add Action**, then **Speak Text**. Make sure its input is **Contents of URL**. Expand it and turn **Wait Until Finished** on.
11. Tap **▶︎** at the bottom to test: the phone should speak a sentence about docks. Then tap **✓** to save.

## Part 2: "Dock Finder" Siri shortcut

This is a regular shortcut, built from the **Shortcuts** tab (not an automation).

1. Tap **+**. Tap the name at the top, then **Rename** to **Dock Finder**.
2. Add **Ask for Input**: type **Text**, prompt `What do you need?`.
3. Add **Get Current Location**.
4. Add **Get Contents of URL**:
   - URL: the **Siri** URL from the table above.
   - Expand it: **Method = POST**, **Request Body = JSON**.
   - Add four **Text** fields:
     - `text`: tap the value, choose **Select Variable**, then tap the **Provided Input** bubble.
     - `lat`: **Select Variable**, tap **Current Location**, then tap the inserted bubble again and choose **Latitude**.
     - `lon`: same as `lat`, but choose **Longitude**.
     - `sessionId`: type the user's first name.
5. Add **Speak Text** with **Contents of URL**, and turn **Wait Until Finished** on.
6. Tap **✓** to save.
7. **Run it once by tapping it in the Shortcuts app** (not via Siri), and answer "find me a dock near me". iOS will ask permission for location and to connect to your n8n host. Choose **Always Allow** for both. These prompts need a tap, which the user can't do mid-ride, so get them out of the way now.
8. Test hands-free: "Hey Siri, **run Dock Finder**".

Things the user can say after "What do you need?":

| Say | What happens |
|---|---|
| "find me a dock near me" | Nearest station with ≥2 open docks to their current location |
| "find me a dock near Union Square" | Nearest station with space near that place |
| "is Mercer and Bleecker full?" | Checks that station; suggests an alternative if it's full |
| "how many bikes are out?" | Citywide totals |
| "my school dock is Mercer and Bleecker" | Remembers it; later "check my school dock" works |
| "what can you do?" | Short spoken help |

## Part 3 (optional): Action Button, nearest dock in one press

For iPhones with an Action Button. No question, no Siri: one press speaks the nearest dock with space to where the user is right now.

1. In the **Shortcuts** tab, tap **+** and name it e.g. **DF (Action Button)**.
2. Add **Get Current Location**.
3. Add **Get Contents of URL** with the **arrival** URL (not the Siri one). Expand it: **Method = POST**, **Request Body = JSON**, and add two **Text** fields:
   - `lat`: **Current Location**, tapped and set to **Latitude**
   - `lon`: **Current Location**, tapped and set to **Longitude**

   Leave out `place`, `destLat` and `destLon`; with no destination it searches around the user's current position.
4. Add **Speak Text** with **Contents of URL**, and turn **Wait Until Finished** on.
5. Tap **▶︎** to test (expect something like "West 15th and 6th has 56 docks open, right there."), then **✓**.
6. Settings → **Action Button** → swipe to **Shortcut** → choose it.

## Known pitfalls (all of these happened during our setup)

| Symptom | Cause | Fix |
|---|---|---|
| Safari opens instead of speaking | Used the **Open URLs** action | Delete it, then use **Get Contents of URL** |
| Works only sometimes, or "webhook not registered" | URL contains `/webhook-test/` | Use `/webhook/`; the test URL only works while the n8n editor is listening |
| Arrival automation answers oddly | Pasted the **Siri** URL into the arrival automation, or the reverse | Arrival uses `citibike-arrival`, Dock Finder uses `citibike-siri` |
| "The network connection was lost" during Get Contents of URL, while the arrival automation works fine | Something in that particular shortcut was broken (never fully identified) | **Build a fresh shortcut step by step, testing with ▶︎ after each step**: (1) only Get Contents of URL with `text` typed as `is mercer and bleecker full?` and `sessionId`, plus Speak Text; (2) add Ask for Input and switch `text` to Provided Input; (3) add Get Current Location plus `lat`/`lon`. Then delete the broken shortcut and give the new one its name. This fixed it for us. |
| Siri does something else (texts someone, searches Maps for "dog") | Siri treats the name as a built-in command or mishears it | Name it **Dock Finder** and always say "**run** Dock Finder". Avoid names starting with "find", "text", "call" or "open", avoid "dock" on its own (heard as "doc" or "dog"), and avoid "Citi Bike" (may open the Citi Bike app) |
| Siri version doesn't know where you are | `lat`/`lon` missing, or location permission not granted | Re-add the fields; run once in the app and choose **Always Allow** |
| Siri works with the phone unlocked but not in your pocket | **Allow Siri When Locked** is off | Turn it on (Part 0) |
| "Near me" answers point to a station far away | Shortcuts has approximate location only | Turn on **Precise Location** for Shortcuts (Part 0) |
| A popup asks to confirm before running | Automation set to Run After Confirmation | Edit the trigger and choose **Run Immediately** |
| Wrong station in arrival answers | Coordinates swapped, or the minus sign dropped from the longitude | Latitude ≈ 40.x, longitude ≈ −73.x in NYC |

To check whether a request even reached the backend, the workflow owner can open **Executions** in n8n. If nothing shows up at the time of the failure, the problem is on the phone.

## Optional: test the backend from a computer

```bash
curl -X POST "https://YOUR-N8N-HOST/webhook/citibike-arrival" -H "Content-Type: application/json" -d '{"place":"school","destLat":40.7289502,"destLon":-73.9960792,"usualDock":"Mercer St & Bleecker St"}'
```

```bash
curl -X POST "https://YOUR-N8N-HOST/webhook/citibike-siri" -H "Content-Type: application/json" -d '{"text":"find me a dock near me","lat":40.738,"lon":-73.996,"sessionId":"test"}'
```

Each should return one sentence within about 2–5 seconds.

## Good to know

- Arrival answers take ~2–3 s; Siri answers ~3–5 s (Siri ones go through an AI model to understand the request).
- "Usual dock" memory from the Siri conversation resets whenever the n8n server restarts. For arrivals, the usual dock lives in the automation itself (`usualDock`), so it never resets.
- A station only counts as available if it's accepting returns and has **at least 2** open docks; the search radius is 1.2 km.
- Distances are straight-line, not riding distance.
- The URLs have no password. Anyone who has them can ask for dock info, which uses the group's AI credits for Siri requests, so share them only within the group.
