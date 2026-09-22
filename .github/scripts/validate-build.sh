#!/usr/bin/env bash
# Validates that a built API Workflow can actually RUN — the checks `uip
# api-workflow validate` cannot make, because to it a placeholder is a valid
# string and an invented connector is a well-formed object.
#
# Reports every problem it finds (not just the first) and exits 1 if any is fatal.
#
# Usage: .github/scripts/validate-build.sh <code-dir> [architectural-considerations.md]
#
# The connection table in architectural-considerations.md §4 is the single source
# of truth for which connections exist. This script reads it rather than carrying
# its own copy, so adding a connection is one edit, in the file the agents read.
#
# Exit 0 = nothing fatal (warnings may still be printed).
# Exit 1 = at least one fatal problem; the message names the file, the activity
#          and what to write instead, because the repair agent reads this output
#          and has one pass to fix it before the PR opens.
set -uo pipefail

CODE_DIR="${1:?usage: validate-build.sh <code-dir> [considerations.md]}"
CONSIDERATIONS="${2:-docs/architectural-considerations.md}"

# §8's sizing expectation. Over this is reported, never fatal — see the note at
# the size check for why.
# Twenty, not twelve. Twelve predated any real build of this shape; a correct one
# came in at nineteen. An API Workflow carries three structural activities (Sequence,
# WorkflowStart, Response) plus one aliasing Assign per value each script returns -
# see §8 "Sizing expectation", which explains why those Assigns are deliberate.
# Reported, never fatal.
ACTIVITY_BUDGET="${MAX_WORKFLOW_ACTIVITIES:-20}"

FATAL=0
WARNED=0

fatal() { echo "::error::$*"; FATAL=1; }
warn()  { echo "::warning::$*"; WARNED=1; }

# ── The approved connections ────────────────────────────────────────────────
# Parsed out of the §4 markdown table. Rows look like:
#   | `coupa-uipath-test` | Coupa | `uipath-coupa-coupa` | `5fadfc73-...` | Enabled |
CONN_TABLE=""
if [ -f "$CONSIDERATIONS" ]; then
  CONN_TABLE=$(sed -n 's/^| *`\([a-z0-9_-]*\)` *| *\([^|]*\)| *`\([a-z-]*\)` *| *`\([0-9a-f-]\{36\}\)`.*/\1\t\3\t\4/p' "$CONSIDERATIONS")
fi

if [ -z "$CONN_TABLE" ]; then
  warn "No connection table found in $CONSIDERATIONS - connection ids cannot be checked. Is §4 still there?"
else
  echo "Approved connections ($(echo "$CONN_TABLE" | wc -l | tr -d ' ')):"
  echo "$CONN_TABLE" | while IFS=$'\t' read -r n k i; do echo "  $n  $k  $i"; done
fi

APPROVED_IDS=$(echo "$CONN_TABLE" | cut -f3)
APPROVED_KEYS=$(echo "$CONN_TABLE" | cut -f2)

# ── Every workflow in the build ─────────────────────────────────────────────
FOUND=0
while IFS= read -r WF; do
  [ -n "$WF" ] || continue
  FOUND=1
  echo ""
  echo "=== $WF ==="

  python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$WF" 2>/dev/null \
    || { fatal "$WF is not valid JSON."; continue; }

  # ── 1. Unresolved placeholders ────────────────────────────────────────────
  # A `<TODO: ...>` connection id or activity id is a guess the builder left for
  # someone else. Studio Web renders it as a broken connection and the run 401s.
  # `uip api-workflow validate` passes it happily: it is a well-formed string.
  PLACEHOLDERS=$(grep -on '<TODO[^"]*\|<REPLACE_WITH_[^"]*\|<FILL_IN[^"]*' "$WF" || true)
  if [ -n "$PLACEHOLDERS" ]; then
    while IFS= read -r line; do
      fatal "$WF:${line%%:*} unresolved placeholder - $(echo "${line#*:}" | cut -c1-110)"
    done <<< "$PLACEHOLDERS"
    fatal "$WF cannot run: a placeholder is not a value. Every connection id comes from the §4 table in $CONSIDERATIONS; if the value you need is not there, say so in build-notes.md instead of inventing a marker."
  fi

  # ── 2. Connector activities ───────────────────────────────────────────────
  # Read the workflow once and report every connector call's shape.
  python3 - "$WF" "$APPROVED_IDS" "$APPROVED_KEYS" <<'PY'
import json, sys, re

wf_path, approved_ids, approved_keys = sys.argv[1], sys.argv[2], sys.argv[3]
ids  = {i for i in approved_ids.split() if i}
keys = {k for k in approved_keys.split() if k}
doc  = json.load(open(wf_path))

problems = []

def walk(node):
    if isinstance(node, dict):
        for key, val in node.items():
            if isinstance(val, dict) and "call" in val:
                yield key, val
            if isinstance(val, (dict, list)):
                yield from walk(val)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)

SHAPE = ("The approved shape is the HTTP Request activity with connector authentication - "
         "see architectural-considerations.md §4, which carries it verbatim.")

for key, act in walk(doc):
    call  = act.get("call")
    with_ = act.get("with") or {}
    bp    = with_.get("bodyParameters") or {}
    conn  = str(with_.get("connectionId", ""))

    if call == "UiPath.IntSvc":
        problems.append(f"{key}: call UiPath.IntSvc is a curated vendor activity. This runner "
                        f"has no credentials to resolve one, so its activity id and configuration "
                        f"would be a guess. {SHAPE}")
        continue

    if call != "UiPath.Http":
        continue

    if with_.get("connector") != "uipath-uipath-http":
        problems.append(f"{key}: with.connector is {with_.get('connector')!r}, must be "
                        f"'uipath-uipath-http'. That field names the HTTP connector itself, "
                        f"never the system being called - that one goes in "
                        f"bodyParameters.targetConnector.")

    if conn == "ImplicitConnection":
        problems.append(f"{key}: connectionId 'ImplicitConnection' is the anonymous HTTP request, "
                        f"which sends no credentials. Every system here needs authentication. {SHAPE}")
    elif ids and conn not in ids:
        problems.append(f"{key}: connectionId {conn[:40]!r} is not one of the approved "
                        f"connections. Use the id from the §4 table for this system.")

    if bp.get("authentication") != "connector":
        problems.append(f"{key}: bodyParameters.authentication is "
                        f"{bp.get('authentication')!r}, must be 'connector'. Without it the "
                        f"request goes out unauthenticated. {SHAPE}")

    target = str(bp.get("targetConnector", ""))
    if keys and target and target not in keys:
        near = [k for k in keys if target.split("-")[-1] in k]
        problems.append(f"{key}: bodyParameters.targetConnector {target!r} is not in the §4 table"
                        + (f" - did you mean {near[0]!r}?" if near else "")
                        + ".")
    elif not target:
        problems.append(f"{key}: bodyParameters.targetConnector is missing - it names the "
                        f"connector of the system being called.")

    # the same connection id has to appear in all three places, or the designer and the
    # deploy binding disagree about which connection this activity uses
    trio = {conn, str(with_.get("connectionResourceId", "")), str(bp.get("connection", ""))}
    if len(trio) != 1:
        problems.append(f"{key}: connectionId, connectionResourceId and "
                        f"bodyParameters.connection must all be the same id; found {sorted(trio)}.")

    if with_.get("endpoint") != "/http-request" or with_.get("method") != "POST":
        problems.append(f"{key}: with.method/with.endpoint must be POST /http-request - that is "
                        f"the HTTP connector's own operation. The verb and URL of YOUR call go in "
                        f"bodyParameters.method and bodyParameters.url.")

    url  = str(bp.get("url", ""))
    path = str(bp.get("path", ""))
    if not url:
        problems.append(f"{key}: bodyParameters.url is required - it is the resource path being called.")
    if not bp.get("method"):
        problems.append(f"{key}: bodyParameters.method is required - the verb of your call.")

    # The connection already knows its base URL. An absolute URL here arrives EMPTY in
    # Studio Web - it validates, it packs, and the request URL field is blank at run
    # time. A shipped solution had to be opened and fixed by hand for this.
    if url.startswith(("http://", "https://")):
        problems.append(f"{key}: bodyParameters.url is the absolute URL {url!r}. It must be the "
                        f"resource path RELATIVE to the connector's base URL - e.g. 'invoices', "
                        f"not 'https://.../api/invoices'. An absolute URL lands empty in the "
                        f"designer. See architectural-considerations.md §4.")
    elif url.startswith("/"):
        problems.append(f"{key}: bodyParameters.url {url!r} has a leading slash - drop it "
                        f"('invoices', not '/invoices').")
    if not path:
        problems.append(f"{key}: bodyParameters.path is required and must carry the same "
                        f"relative resource path as bodyParameters.url.")
    elif path != url:
        problems.append(f"{key}: bodyParameters.path {path!r} and bodyParameters.url {url!r} "
                        f"must be the same relative resource path.")

    # Slack takes a member/channel ID. An email is accepted by the document, the SDD and
    # the build, and rejected by Slack at run time.
    if "slack" in target.lower():
        body = json.dumps(bp.get("body", ""))

        # `${{ ... }}` is the expression delimiter `${ }` plus the object literal's
        # own brace. Pasting a JSON payload in whole brings a SECOND pair, giving
        # `${{ { ... } }}` - a SyntaxError the expression editor reports as
        # "Unexpected token '{'". Build and deploy both pass; the activity fails at
        # run time. Checked on the RAW value, before json.dumps escapes anything.
        raw_body = bp.get("body", "")
        if isinstance(raw_body, str) and re.match(r'^\s*\$\{\{\s*\{', raw_body):
            problems.append(
                f"{key}: bodyParameters.body starts `${{{{ {{` - the object literal is "
                f"wrapped in a second pair of braces. `${{{{` already opens the object, "
                f"so write the key/value pairs directly: "
                f"`${{{{ channel: '...', text: `...`, blocks: [ ... ] }}}}`. "
                f"See architectural-considerations.md §4, \"The Slack message is Block Kit\".")

        m = re.search(r"channel\s*:\s*['\"]?([^'\",}\s]+)", body)
        if m and "@" in m.group(1):
            problems.append(f"{key}: Slack channel is {m.group(1)!r}, an email address. "
                            f"chat.postMessage needs a member ID or channel ID (e.g. WLX9BD8FN). "
                            f"See architectural-considerations.md §4.")

        # The message is Block Kit. §4 shows a SHORTENED one-line body next to the
        # activity shape so the shape stays readable, and a build copied that and
        # shipped an unformatted wall of prose to a live Slack channel. The real
        # payload is §4's "The Slack message is Block Kit" object: channel + text +
        # blocks together as the value of bodyParameters.body.
        if "chat.postmessage" in (str(bp.get("path", "")) + str(bp.get("url", ""))).lower():
            if '"blocks"' not in body and "blocks:" not in body and "'blocks'" not in body:
                problems.append(
                    f"{key}: the chat.postMessage body has no `blocks` - this renders as "
                    f"unformatted prose in Slack. bodyParameters.body must be the whole "
                    f"Block Kit payload (channel + text + blocks together) from "
                    f"architectural-considerations.md §4 \"The Slack message is Block Kit, "
                    f"and it goes in `body`\", not the shortened one-line form shown next "
                    f"to the activity shape.")
            else:
                # `text` is also a key on every nested header/button element, so a
                # naive substring search always finds one. The top-level fallback is
                # the one that appears BEFORE `blocks` in the canonical payload
                # (channel, text, blocks). Advisory, not fatal: the ordering is a
                # convention, and a false failure here would block a good build over
                # a push-notification string.
                pre = body.split("blocks", 1)[0]
                if not re.search(r"['\"]?text['\"]?\s*:", pre):
                    print(f"::warning::{wf_path} {key}: the chat.postMessage body has "
                          f"`blocks` but no top-level `text` ahead of them. With blocks "
                          f"present, `text` is the push-notification fallback; without "
                          f"it the notification reads \"This content can't be displayed\". "
                          f"See architectural-considerations.md §4.")

# ── activity names are resolved as exact strings, case included ─────────────
# `$context.outputs.http_request_slack` against an activity named
# HTTP_Request_Slack reads undefined: no build error, no validate error, a
# confusing failure at run time. A shipped solution needed this fixed by hand.
raw = open(wf_path, encoding="utf-8").read()

def named(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, dict) and isinstance(v.get("export"), dict):
                yield k, v
            if isinstance(v, (dict, list)):
                yield from named(v)
    elif isinstance(node, list):
        for item in node:
            yield from named(item)

# Built from the DECODED export strings: in the raw file their quotes are escaped
# (\"Name\": $output), so a regex over the file text silently finds nothing.
exported = set()
for _k, _a in named(doc):
    exported.update(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:\s*\$output',
                               (_a.get("export") or {}).get("as", "")))

for key, act in named(doc):
    as_ = (act.get("export") or {}).get("as", "")
    own = re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:\s*\$output', as_)
    if not own:
        continue                       # exports variables, not a named output
    base = key.split("#")[0]           # If_1#Wrapper exports as "If_1"
    if base not in own:
        problems.append(f"{key}: its export writes outputs.{own[0]!r} but the activity is "
                        f"named {base!r}. The export key is the activity name character for "
                        f"character, same case.")

for ref in sorted(set(re.findall(r'\$context\??\.outputs\??\.([A-Za-z_][A-Za-z0-9_]*)', raw))):
    if ref in exported:
        continue
    same = [e for e in exported if e.lower() == ref.lower()]
    if same:
        problems.append(f"$context.outputs.{ref} does not exist - the activity exports "
                        f"{same[0]!r}. Activity names are CASE SENSITIVE; this reads undefined "
                        f"at run time and fails nothing until then.")
    else:
        problems.append(f"$context.outputs.{ref} does not exist - no activity exports that "
                        f"name. Exported names are: {', '.join(sorted(exported)) or '(none)'}.")

for p in problems: print(f"::error::{wf_path} {p}")
sys.exit(1 if problems else 0)
PY
  [ $? -eq 0 ] || FATAL=1

  # ── 3. Size ───────────────────────────────────────────────────────────────
  # Reported, never fatal. The last oversized build was oversized because the
  # source document asked for it - "Three retries and explicit error route" in
  # scope, BR-009 "Retry Coupa and Slack failures up to three times" - and a gate
  # that fails a build for obeying its own spec trains the builder to drop
  # requirements. The number belongs in front of a human, on the PR; the fix for
  # a genuinely oversized process belongs in the PDD, not here.
  COUNT=$(grep -c '"activityType"' "$WF" || true)
  echo "Activities: $COUNT (§8 expects <= $ACTIVITY_BUDGET)"
  if [ "$COUNT" -gt "$ACTIVITY_BUDGET" ]; then
    echo "Breakdown:"
    grep -o '"activityType": *"[^"]*"' "$WF" | sed 's/.*: *"//;s/"//' | sort | uniq -c | sort -rn | sed 's/^/  /'
    warn "$WF has $COUNT activities, over §8's $ACTIVITY_BUDGET. If a retry loop, a per-call try/catch or a third outcome is in there, check the SDD names the business rule that forced it - and that the rule is one the process actually needs. An API Workflow's httpRetryConfig replaces a Do_While + Wait + counter."
  fi

done < <(find "$CODE_DIR" -maxdepth 5 -type f -name 'Workflow.json' | sort)

echo ""
if [ "$FOUND" -eq 0 ]; then
  echo "No Workflow.json under $CODE_DIR - nothing to validate."
  exit 0
fi

if [ "$FATAL" -eq 1 ]; then
  echo "validate-build: FAILED - the workflow above cannot run as built."
  exit 1
fi
[ "$WARNED" -eq 1 ] && echo "validate-build: passed with warnings." || echo "validate-build: passed."
exit 0
