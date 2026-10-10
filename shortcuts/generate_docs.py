#!/usr/bin/env python3
"""Regenerate the generated sections of docs/shortcuts.md from the code.

Reads the shortcut definitions in shortcuts/build_shortcuts.py, the webhooks and
Code nodes in n8n/citibike-smart-dock-assistant.workflow.json, and the Siri
phrases in the iOS app, then rewrites everything between the
`<!-- generated:start -->` and `<!-- generated:end -->` markers. Hand-written
text outside the markers is kept. CI runs this on every push
(.github/workflows/shortcut-docs.yml) and commits the result if it changed.

    python3 shortcuts/generate_docs.py           # rewrite docs/shortcuts.md
    python3 shortcuts/generate_docs.py --check   # exit 1 if it's out of date
"""
import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "shortcuts"))
import build_shortcuts as b  # noqa: E402

DOC = REPO / "docs" / "shortcuts.md"
START, END = "<!-- generated:start -->", "<!-- generated:end -->"
HOST = "YOUR-N8N-HOST"
APP_PROVIDER = REPO / "ios" / "biker-app" / "Intents" / "DockFinderShortcutsProvider.swift"
APP_INTENTS = REPO / "ios" / "biker-app" / "Intents"

ACTION_NAMES = {
    "is.workflow.actions.gettext": "Text",
    "is.workflow.actions.ask": "Ask for Input",
    "is.workflow.actions.getcurrentlocation": "Get Current Location",
    "is.workflow.actions.downloadurl": "Get Contents of URL",
    "is.workflow.actions.speaktext": "Speak Text",
}


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def step_of(actions):
    return {a["WFWorkflowActionParameters"]["UUID"]: i + 1 for i, a in enumerate(actions)}


def describe_value(v, steps, actions):
    """Explain a Shortcuts text value: a literal, or a variable from an earlier step."""
    val = v["Value"]
    attachments = val.get("attachmentsByRange") or {}
    if not attachments:
        return f'`"{val.get("string", "")}"` (fixed)'
    parts = []
    for var in attachments.values():
        step = steps.get(var.get("OutputUUID"), "?")
        chain = [f'**{var.get("OutputName")}** from step {step}']
        for ag in var.get("Aggrandizements", []):
            if ag["Type"] == "WFCoercionVariableAggrandizement":
                chain.append("as a Location (the phone geocodes the address)")
            elif ag["Type"] == "WFPropertyVariableAggrandizement":
                chain.append(f'→ {ag["PropertyName"]}')
        parts.append(" ".join(chain))
    return "; ".join(parts)


def describe_action(i, a, steps, actions, questions):
    ident, p = a["WFWorkflowActionIdentifier"], a["WFWorkflowActionParameters"]
    name = ACTION_NAMES.get(ident, ident)
    if ident == "is.workflow.actions.gettext":
        q = questions.get(i)
        what = (f'Holds the answer to setup question {q[0]}' if q else f'`{p.get("WFTextActionText", "")}`')
        out = 'Output: **Text**'
    elif ident == "is.workflow.actions.ask":
        what = f'Siri asks **"{p["WFAskActionPrompt"]}"** and listens (input type: {p["WFInputType"]})'
        out = 'Output: **Provided Input** (what the rider said)'
    elif ident == "is.workflow.actions.getcurrentlocation":
        what = "Gets the phone's GPS position (needs Location permission for Shortcuts, Precise on)"
        out = 'Output: **Current Location**'
    elif ident == "is.workflow.actions.downloadurl":
        what = f'**{p["WFHTTPMethod"]}** `{p["WFURL"]}`, Request Body **{p["WFHTTPBodyType"]}** (fields below)'
        out = 'Output: **Contents of URL** (the server\'s one-sentence reply, plain text)'
    elif ident == "is.workflow.actions.speaktext":
        what = (f'Speaks {describe_value(p["WFText"], steps, actions)} through the current audio output '
                f'(AirPods/headphones). Wait Until Finished: **{"on" if p.get("WFSpeakTextWait") else "off"}**')
        out = "Last step"
    else:
        what, out = "(not described)", ""
    return f"| {i + 1} | {name} | {cell(what)} | {cell(out)} |"


def shortcut_section(n, item):
    wf = item["workflow"]
    actions = wf["WFWorkflowActions"]
    steps = step_of(actions)
    questions = {q["ActionIndex"]: (k + 1, q) for k, q in enumerate(wf["WFWorkflowImportQuestions"])}
    doc = (item["build"].__doc__ or "").strip()
    out = [f"### {n}. {item['name']}", "", f"- **What it does:** {doc}", f"- **How it runs:** {item['trigger']}", ""]

    out += ["**Setup questions** (asked once, when the rider adds the shortcut):", ""]
    if questions:
        out += ["| # | Question | Fills step |", "|---|---|---|"]
        for idx, (k, q) in sorted(questions.items(), key=lambda kv: kv[1][0]):
            out.append(f"| {k} | {cell(q['Text'])} | {idx + 1} ({ACTION_NAMES.get(actions[idx]['WFWorkflowActionIdentifier'])}) |")
    else:
        out.append("None.")
    out += ["", "**Steps, in order:**", "", "| Step | Action | What it does | Output |", "|---|---|---|---|"]
    out += [describe_action(i, a, steps, actions, questions) for i, a in enumerate(actions)]

    for a in actions:
        p = a["WFWorkflowActionParameters"]
        if a["WFWorkflowActionIdentifier"] != "is.workflow.actions.downloadurl":
            continue
        out += ["", f"**Request sent** (step {steps[p['UUID']]}): `{p['WFHTTPMethod']} {p['WFURL']}`", "",
                "| JSON field | Value |", "|---|---|"]
        for f in p["WFJSONValues"]["Value"]["WFDictionaryFieldValueItems"]:
            out.append(f"| `{f['WFKey']['Value']['string']}` | {cell(describe_value(f['WFValue'], steps, actions))} |")

    out += ["", "```mermaid", "flowchart LR"]
    for i, a in enumerate(actions):
        out.append(f'  s{i + 1}["{i + 1}. {ACTION_NAMES.get(a["WFWorkflowActionIdentifier"], "?")}"]')
    out.append("  " + " --> ".join(f"s{i + 1}" for i in range(len(actions))))
    out += ["```", ""]
    return out


def code_node_file(name):
    f = REPO / "n8n" / "code-nodes" / (re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") + ".js")
    return f if f.exists() else None


def backend_section():
    wf = json.loads(b.WORKFLOW.read_text())
    nodes = {n["name"]: n for n in wf["nodes"]}
    conns = wf["connections"]
    out = ["## Backend endpoints the shortcuts call", "",
           f"Read from `{b.WORKFLOW.relative_to(REPO)}`. URLs use `{HOST}` in place of the group's real n8n host.", ""]
    for name, n in nodes.items():
        if n["type"] != "n8n-nodes-base.webhook":
            continue
        p = n["parameters"]
        # every route a request can take from this webhook to the node that sends the reply
        paths, stack = [], [[name]]
        while stack:
            path = stack.pop()
            nexts = [c["node"] for outs in conns.get(path[-1], {}).get("main", []) for c in outs]
            if not nexts:
                if nodes[path[-1]]["type"] == "n8n-nodes-base.respondToWebhook":
                    paths.append(path[1:])
                continue
            stack += [path + [n] for n in reversed(nexts) if n not in path]
        order = list(dict.fromkeys(n for path in paths for n in path))
        users = [c["name"] for c in b.catalog(f"https://{HOST}/webhook/{b.webhook_paths()[0]}",
                                               f"https://{HOST}/webhook/{b.webhook_paths()[1]}")
                 if any(a["WFWorkflowActionParameters"].get("WFURL", "").endswith("/" + p["path"])
                        for a in c["workflow"]["WFWorkflowActions"])]
        out += [f"### `{p.get('httpMethod', 'GET')} /webhook/{p['path']}` (n8n node: {name})", "",
                f"- **Called by:** {', '.join(users) or 'no shared shortcut'}",
                f"- **Responds:** plain text, one sentence (response mode `{p.get('responseMode')}`)",
                f"- **Routes a request can take** ({len(paths)}; each ends in the reply):", ""]
        for path in paths:
            out.append("  - " + " → ".join(path))
        out += ["", "- **Code nodes on those routes:**", ""]
        for node in order:
            nn = nodes[node]
            if nn["type"] != "n8n-nodes-base.code":
                continue
            f = code_node_file(node)
            out.append(f"  - {node}" + (f" ([code](../{f.relative_to(REPO)}))" if f else ""))
        out.append("")
        spoken = []
        for node in order:
            code = nodes[node]["parameters"].get("jsCode", "")
            # `text` is the long chat reply unless the node speaks it as-is (spokenText:text)
            text_is_spoken = "spokenText:text" in code.replace(" ", "")
            for line in code.splitlines():
                t = line.strip()
                if "`" not in t:
                    continue
                if (re.match(r"(const\s+)?spokenText\s*=", t) or "spokenText:`" in t
                        or re.match(r"[?:]\s*\(?\s*(lead|req\.alias|`)", t)
                        or (text_is_spoken and re.match(r"text\s*=", t))):
                    spoken.append((node, t))
        if spoken:
            out += ["- **Sentence templates it can speak** (straight from the code; `${...}` is filled from live data):", ""]
            out += [f"  - *{node}:* `{cell(t)}`" for node, t in spoken]
            out.append("")
    rules = []
    for name, n in nodes.items():
        for line in n["parameters"].get("jsCode", "").splitlines():
            t = line.strip()
            if re.search(r"(const canReturn|<=\s*1200|const problem)", t):
                rules.append((name, t))
    if rules:
        out += ["### Dock rules (from the Code nodes)", "",
                "A station is only suggested if it passes `canReturn`; searches stay within the distance shown.", ""]
        out += [f"- *{node}:* `{cell(t)}`" for node, t in rules]
        out.append("")
    return out


def app_section():
    out = ["## Native app Siri phrases (developer preview)", "",
           "Not needed for the shared shortcuts above. Listed so everyone knows which phrases the app claims "
           f"(read from `{APP_PROVIDER.relative_to(REPO)}`). `Dock Finder` stands for the app name.", ""]
    if not APP_PROVIDER.exists():
        return out + ["App source not found.", ""]
    titles = {}
    for f in APP_INTENTS.glob("*.swift"):
        for m in re.finditer(r"struct\s+(\w+)\s*:\s*AppIntent.*?static\s+(?:let|var)\s+title[^=]*=\s*\"([^\"]+)\"",
                             f.read_text(), re.S):
            titles[m.group(1)] = m.group(2)
    src = APP_PROVIDER.read_text()
    blocks = re.findall(r"AppShortcut\(\s*intent:\s*(\w+)\(.*?phrases:\s*\[(.*?)\]", src, re.S)
    if not blocks:
        return out + ["Couldn't read the phrases from the app source.", ""]
    out += ["| Shortcuts action | Siri phrases |", "|---|---|"]
    for intent, phrases in blocks:
        said = [p.replace("\\(.applicationName)", "Dock Finder").replace("\\(\\.$place)", "<place>")
                for p in re.findall(r'"((?:[^"\\]|\\.)*)"', phrases)]
        out.append(f"| {titles.get(intent, intent)} | {cell('; '.join(f'“{s}”' for s in said))} |")
    return out + [""]


def generated():
    arrival, siri = b.webhook_paths()
    items = b.catalog(f"https://{HOST}/webhook/{arrival}", f"https://{HOST}/webhook/{siri}")
    out = [START, "",
           "<!-- Everything between these markers is rewritten by shortcuts/generate_docs.py. "
           "Edit shortcuts/build_shortcuts.py, the n8n workflow, or the app instead. -->", "",
           "## Shortcut reference", "",
           f"{len(items)} shared shortcuts, defined in `shortcuts/build_shortcuts.py`:", "",
           "| Shortcut | How it runs |", "|---|---|"]
    out += [f"| [{c['name']}](#{i + 1}-{re.sub(r'[^a-z0-9 -]', '', c['name'].lower()).replace(' ', '-')}) | {cell(c['trigger'])} |"
            for i, c in enumerate(items)]
    out.append("")
    for i, c in enumerate(items):
        out += shortcut_section(i + 1, c)
    out += backend_section() + app_section() + [END]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="exit 1 if docs/shortcuts.md is out of date")
    args = ap.parse_args()
    current = DOC.read_text()
    if START not in current or END not in current:
        sys.exit(f"{DOC} is missing the {START} / {END} markers")
    head, rest = current.split(START, 1)
    tail = rest.split(END, 1)[1]
    updated = head + generated() + tail
    if args.check:
        sys.exit(0 if updated == current else f"{DOC.relative_to(REPO)} is out of date; run python3 shortcuts/generate_docs.py")
    if updated != current:
        DOC.write_text(updated)
        print(f"updated {DOC.relative_to(REPO)}")
    else:
        print(f"{DOC.relative_to(REPO)} already up to date")


if __name__ == "__main__":
    main()
