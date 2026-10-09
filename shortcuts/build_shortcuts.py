#!/usr/bin/env python3
"""Build the group's iPhone shortcuts as signed .shortcut files.

Each file asks its setup questions when someone adds it (first name, the
address of a place, an optional usual dock), so a new rider never types a URL
or coordinates. The webhook paths are read from the n8n workflow in this repo,
so rebuilding after a `git pull` always matches the current backend.

    git pull
    python3 shortcuts/build_shortcuts.py --host yourname.app.n8n.cloud

Output goes to shortcuts/dist/ (gitignored: the files contain the n8n host,
and the webhooks have no password). Signing uses macOS's `shortcuts sign`.

docs/shortcuts.md describes every shortcut built here; it's regenerated from
this file by shortcuts/generate_docs.py (and by CI on every push).
"""
import argparse
import json
import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WORKFLOW = REPO / "n8n" / "citibike-smart-dock-assistant.workflow.json"
OBJ = "￼"  # Shortcuts' placeholder character for an inline variable


def webhook_paths():
    nodes = {n["name"]: n for n in json.loads(WORKFLOW.read_text())["nodes"]}
    return nodes["arrival webhook"]["parameters"]["path"], nodes["siri webhook"]["parameters"]["path"]


def text(s):
    return {"Value": {"string": s}, "WFSerializationType": "WFTextTokenString"}


def output(action, name, *aggrandizements):
    return {"Type": "ActionOutput", "OutputUUID": action["WFWorkflowActionParameters"]["UUID"],
            "OutputName": name, "Aggrandizements": list(aggrandizements)}


def token(var):
    return {"Value": {"string": OBJ, "attachmentsByRange": {"{0, 1}": var}},
            "WFSerializationType": "WFTextTokenString"}


def prop(name):
    return {"Type": "WFPropertyVariableAggrandizement", "PropertyName": name}


AS_LOCATION = {"Type": "WFCoercionVariableAggrandizement", "CoercionItemClass": "WFLocationContentItem"}


def action(identifier, **params):
    params["UUID"] = str(uuid.uuid4()).upper()
    return {"WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": params}


def text_action(default=""):
    return action("is.workflow.actions.gettext", WFTextActionText=default)


def post_json(url, fields):
    items = [{"WFItemType": 0, "WFKey": text(k), "WFValue": v if isinstance(v, dict) else text(v)}
             for k, v in fields.items()]
    return action("is.workflow.actions.downloadurl", WFURL=url, WFHTTPMethod="POST", WFHTTPBodyType="JSON",
                  ShowHeaders=True,
                  WFJSONValues={"Value": {"WFDictionaryFieldValueItems": items},
                                "WFSerializationType": "WFDictionaryFieldValue"})


def speak(download):
    return action("is.workflow.actions.speaktext", WFText=token(output(download, "Contents of URL")),
                  WFSpeakTextWait=True)


def question(actions, target, prompt, default=""):
    return {"ActionIndex": actions.index(target), "Category": "Parameter", "ParameterKey": "WFTextActionText",
            "Text": prompt, "DefaultValue": default}


def workflow(actions, questions=(), color=4282601983, glyph=59511):
    return {
        "WFWorkflowActions": actions,
        "WFWorkflowImportQuestions": list(questions),
        "WFWorkflowClientVersion": "2302.0.4",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": color, "WFWorkflowIconGlyphNumber": glyph},
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFQuickActionSurfaces": [],
    }


def dock_finder(siri_url):
    """Hey Siri, run Dock Finder: asks what you need, sends it with your location."""
    name = text_action()
    ask = action("is.workflow.actions.ask", WFAskActionPrompt="What do you need?", WFInputType="Text")
    here = action("is.workflow.actions.getcurrentlocation")
    post = post_json(siri_url, {
        "text": token(output(ask, "Provided Input")),
        "lat": token(output(here, "Current Location", prop("Latitude"))),
        "lon": token(output(here, "Current Location", prop("Longitude"))),
        "sessionId": token(output(name, "Text")),
    })
    actions = [name, ask, here, post, speak(post)]
    return workflow(actions, [question(actions, name, "Your first name (keeps your Dock Finder memory separate from everyone else's)")])


def nearest_dock(arrival_url):
    """One press (Action Button): nearest dock with space to where you are."""
    here = action("is.workflow.actions.getcurrentlocation")
    post = post_json(arrival_url, {
        "lat": token(output(here, "Current Location", prop("Latitude"))),
        "lon": token(output(here, "Current Location", prop("Longitude"))),
    })
    return workflow([here, post, speak(post)], color=4292093695)


def dock_arrival(arrival_url, place):
    """Run by an Arrive automation: your usual dock near this place, or where to go instead."""
    address = text_action()
    usual = text_action()
    # The address text is turned into a location on the phone (Apple's geocoder), then into lat/lon.
    post = post_json(arrival_url, {
        "place": place,
        "destLat": token(output(address, "Text", AS_LOCATION, prop("Latitude"))),
        "destLon": token(output(address, "Text", AS_LOCATION, prop("Longitude"))),
        "usualDock": token(output(usual, "Text")),
    })
    actions = [address, usual, post, speak(post)]
    return workflow(actions, [
        question(actions, address, f"Address of your {place}, with the city (e.g. 44 W 4th St, New York, NY)"),
        question(actions, usual, f"Your usual Citi Bike dock near your {place}, as it appears in the Citi Bike app "
                                 "(e.g. Mercer St & Bleecker St). Leave blank if you don't have one"),
    ], color=4251333119)


def catalog(arrival_url, siri_url):
    """Every shortcut the group shares, with how a rider triggers it. Used by the build and by generate_docs.py."""
    return [
        {"name": "Dock Finder", "trigger": 'Say "Hey Siri, run Dock Finder", then answer the question out loud.',
         "build": dock_finder, "workflow": dock_finder(siri_url)},
        {"name": "Nearest Dock", "trigger": "Press the Action Button (Settings → Action Button → Shortcut), or tap it.",
         "build": nearest_dock, "workflow": nearest_dock(arrival_url)},
        *[{"name": f"Dock Arrival - {place.title()}",
           "trigger": f"Runs by itself from an Arrive automation set ~500 m around the rider's {place}.",
           "build": dock_arrival, "workflow": dock_arrival(arrival_url, place)}
          for place in ("school", "work", "home")],
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", required=True, help="n8n host, e.g. yourname.app.n8n.cloud (no https://)")
    ap.add_argument("--out", default=str(REPO / "shortcuts" / "dist"))
    ap.add_argument("--unsigned", action="store_true", help="skip signing (files won't open on an iPhone)")
    args = ap.parse_args()

    host = args.host.removeprefix("https://").removeprefix("http://").strip("/")
    arrival_path, siri_path = webhook_paths()
    arrival_url, siri_url = f"https://{host}/webhook/{arrival_path}", f"https://{host}/webhook/{siri_path}"

    out = Path(args.out)
    (out / "unsigned").mkdir(parents=True, exist_ok=True)
    for item in catalog(arrival_url, siri_url):
        name, wf = item["name"], item["workflow"]
        raw = out / "unsigned" / f"{name}.shortcut"
        raw.write_bytes(plistlib.dumps(wf, fmt=plistlib.FMT_BINARY))
        if args.unsigned:
            continue
        signed = out / f"{name}.shortcut"
        result = subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", str(raw), "--output", str(signed)],
                                capture_output=True, text=True)
        if result.returncode != 0 or not signed.exists():
            sys.exit(f"signing {name} failed: {result.stderr.strip() or result.stdout.strip()}")
        print(f"built {signed}")


if __name__ == "__main__":
    main()
