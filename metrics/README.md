# Usage data → Google Sheet

When a rider agrees to share usage data (asked once in the app; changeable under **Privacy** on the home screen), Dock Finder sends a row per event to a Google Sheet. Nothing is sent if they said no, or if the app was built without a sheet address.

## Set up the sheet (about 2 minutes, once per team)

1. Create a new Google Sheet, e.g. "Dock Finder usage".
2. **Extensions → Apps Script**. Delete what's there, paste in [`google-apps-script.js`](google-apps-script.js), and save.
3. **Deploy → New deployment** → gear icon → **Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone**
   - **Deploy**, and approve the permissions it asks for (it only touches this sheet).
4. Copy the **Web app URL** (ends in `/exec`).
5. Set `DOCKFINDER_METRICS_URL` in `ios/Config/DockFinder.xcconfig` to it, **without** `https://` (xcconfig files treat `//` as a comment):
   ```
   DOCKFINDER_METRICS_URL = script.google.com/macros/s/AKfy…/exec
   ```
6. Build and run. Rows appear in an **Events** tab as people use the app.

**The team's sheet is already set up** and its URL is committed in `ios/Config/DockFinder.xcconfig`, so every build reports there with no setup. Only the sheet's owner ever signs in to Google (once, when deploying); riders never do. The repo is public, so anyone who finds the URL could add junk rows, but they can't read anything: the script only appends. To build without sending anywhere, add `DOCKFINDER_METRICS_URL =` to your `Local.xcconfig`. If you change the script later, use **Deploy → Manage deployments → Edit → New version**, so the URL stays the same.

## What a row contains

| Column | Meaning |
|---|---|
| `received`, `date` | When the sheet got it, and when it happened on the phone |
| `event` | What happened (below) |
| `install_id` | Random ID made on that iPhone; the same for all its events. Not a name or Apple ID |
| `app_version` | e.g. `1.0 (3)` |
| `latitude`, `longitude` | Where the rider was (blank if unknown) |
| `station` | The dock Dock Finder sent them to |
| `avoided_station` | The full or closed dock it steered them away from |
| `minutes_saved`, `dollars_saved` | Estimated savings, on `full_dock_avoided` rows |
| `details` | Extra fields as JSON: the spoken answer, Siri intent, destination, etc. |
| `event_id` | Unique per event, for spotting duplicates if a send was retried |

Events: `app_launch`, `sharing_turned_on`, `siri_answer`, `app_answer`, `ride_started`, `ride_arrival_alert`, `ride_ended_early`, `place_arrival_alert`, `directions_started`, `directions_rerouted`, `directions_stopped`, `directions_arrived`, `full_dock_avoided`, `hands_free_check`, `voice_question` (the words asked with the Ask Dock Finder button), `voice_answer`.

## Savings numbers

Each `full_dock_avoided` row is one redirect away from a full or closed dock, and each `hands_free_check` row is one dock answer given by voice (a time the rider didn't take out their phone, credited 1 minute). Both carry the minutes and dollars the app credited (the model is in `ios/biker-app/Models/Savings.swift` and explained on the app's Savings screen). Useful formulas, assuming the default column order:

- Total minutes saved: `=SUM(J2:J)` (only those two events fill this column)
- Total dollars saved: `=SUM(K2:K)`
- From full docks only: `=SUMIF(C:C, "full_dock_avoided", K:K)`
- Times riders didn't take out their phone: `=COUNTIF(C:C, "hands_free_check")`
- Riders who shared data: `=COUNTUNIQUE(D2:D)`
- Average dollars per rider: total dollars ÷ riders
