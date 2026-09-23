#!/usr/bin/env bash
# Validates that the generated SDD(s) are complete enough to hand to development.
# Reports every problem it finds (not just the first) and exits 1 if any.
#
# Usage: .github/scripts/validate-sdd.sh <architecture.json> [current-pdd.md ...]
#
# architecture.json declares which files to validate and with which template, so
# this script never guesses at the section list. Passing the current PDD as well
# turns on traceability checks: a business rule the PDD states and the design never
# mentions is a hole, not a style problem.
set -uo pipefail

ARCH_FILE="${1:?usage: validate-sdd.sh <architecture.json> [pdd.md ...]}"
shift || true
PDD_FILES=("$@")

# The size floor is proportional to the template, not a flat number: a thorough
# 12-section API Workflow SDD is legitimately smaller than an 18-section RPA one,
# and a flat floor tuned to RPA rejects it.
BYTES_PER_SECTION="${MIN_SDD_BYTES_PER_SECTION:-650}"
MIN_ROOT_BYTES="${MIN_SOLUTION_SDD_BYTES:-3000}"

# The epic key is the repository name's prefix - jactiv-572-no-po-invoice-chaser
# -> jactiv-572 -> the resource prefix jactiv_572_. It is the only identifier stable
# across the whole lifecycle: every stage has its own story key, so naming resources
# off a story key means a change-request replay renames live Orchestrator resources.
# The SOLUTION name is no longer the repository name: it is
# <process-base>-<epic-number>, decided by the Architecture stage and carried in
# architecture.json as `solution_name`. It is resolved below, once the contract
# has been read. See architectural-considerations.md §4 "Naming".
REPO_NAME="${EPIC_REPO_NAME:-${GITHUB_REPOSITORY##*/}}"
EPIC_KEY="${EPIC_KEY:-$(printf '%s' "$REPO_NAME" | grep -oiE '^[a-z]+-[0-9]+' || true)}"
RESOURCE_PREFIX=""
[ -n "$EPIC_KEY" ] && RESOURCE_PREFIX="$(printf '%s' "$EPIC_KEY" | tr 'A-Z-' 'a-z_')_"

FAILURES=0
WARNINGS=0
ADVISORIES=0

# ── two severities, on purpose ───────────────────────────────────────────────
# This script exists to DRIVE a good SDD, not to reject one after the fact.
#
#   fail()   the next stage cannot consume the document - uipath-develop literally
#            refuses to build on a missing planner-handoff marker or Status: draft.
#            Letting these through does not save the run, it just moves the failure
#            one stage later where the error is about the wrong thing.
#
#   advise() the document is worse than it should be, but usable. Counts toward the
#            exit code on the FIRST pass, so the repair agent runs and is handed the
#            exact message.
#
# `advise` is a WARNING and nothing more. It never fails the run and never drives
# the repair pass - only `fail` does. SDD_ADVISORY_ONLY is kept so existing callers
# still work, but it no longer changes the outcome, because advisories are already
# non-fatal.
ADVISORY_ONLY="${SDD_ADVISORY_ONLY:-0}"

fail()   { echo "::error::$*"; FAILURES=$((FAILURES + 1)); }
warn()   { echo "::warning::$*"; WARNINGS=$((WARNINGS + 1)); }
advise() { echo "::warning::[quality] $*"; ADVISORIES=$((ADVISORIES + 1)); }
ok()     { echo "  ok  - $*"; }
# Document History naming rides the same advisory channel as every other
# quality finding, so it drives the repair pass and is then downgraded to a
# warning by SDD_ADVISORY_ONLY in the Verify step.
soft_note() { advise "$*"; }

# ── Document History: the record of what changed and why ─────────────────────
# The lifecycle documents are LIVING files at fixed repository-based names - never
# renamed, never superseded by a second file - so this table is the only
# human-readable record of which change request caused which revision. Git has the
# diff; this has the reason.
#
# Two severities on purpose: the table's EXISTENCE and its rows are hard, because a
# document without one loses its history permanently. Whether a revision NAMES its
# change request is advisory, so a first-run document - which has no CR to name -
# can never fail on it.
check_document_history() {
  local f="$1" label="${2:-$1}"

  if ! grep -qxF '## Document History' "$f"; then
    fail "$label is missing '## Document History' - without it a revision leaves no record of what changed."
    return
  fi

  # Data rows only: everything after the table's separator line, up to the next H2.
  local rows n
  rows=$(awk '
    /^## Document History$/           { inside = 1; next }
    inside && /^## /                  { exit }
    inside && /^\|[ :|-]+\|[ :|-]*$/  { sep = 1; next }
    inside && sep && /^\|/            { print }
  ' "$f")
  n=$(printf '%s' "$rows" | grep -c . || true)

  if [ "${n:-0}" -lt 1 ]; then
    fail "$label has an empty Document History table - it needs at least one row."
    return
  fi

  # Every row must actually say something. A dated row with no comment records that
  # a change happened while hiding what it was, which is worse than no row at all.
  local blank
  # The COMMENTS column specifically - the last cell before the trailing pipe -
  # not merely "the last non-empty cell", which a row ending `| Architect | |`
  # would satisfy while saying nothing about what changed.
  blank=$(printf '%s\n' "$rows" | awk -F'|' '{
    if (NF < 3) { print NR; next }
    c = $(NF - 1); gsub(/^[ \t]+|[ \t]+$/, "", c);
    if (c == "") print NR
  }')
  if [ -n "$blank" ]; then
    fail "$label Document History has row(s) with an empty Comments cell: row(s) $(echo "$blank" | tr '\n' ' ')"
  else
    ok "Document History has ${n} row(s), all with comments"
  fi

  # Two or more rows means a revision happened, so the newest row should name what
  # caused it - a CR document, a story key, or a filename.
  if [ "${n:-0}" -ge 2 ]; then
    local newest
    newest=$(printf '%s\n' "$rows" | tail -1)
    if ! printf '%s' "$newest" \
         | grep -qiE '\.md|\.docx|[a-z]+-[0-9]+|change[ -]request|\bCR\b'; then
      soft_note "$label newest Document History row does not name the change request that caused it: ${newest}"
    fi
  fi
}

# THE TARGET SHAPE, fixed for this programme: a UiPath SOLUTION containing exactly
# ONE API Workflow project. `sdd_scope: single-product` means one PROJECT INSIDE that
# solution - it has never meant "no solution". Everything here still ships a solution.
#
# ── the section contract, per template ────────────────────────────────────────
# Kept in sync with uipath-planner assets/templates/*. A generated SDD must be a
# SUPERSET of its template's numbered sections - extra sections are fine, a
# missing one is a defect.
sections_for() {
  case "$1" in
    solution-overview)
      cat <<'EOF'
Solution Overview
Project Inventory
Cross-Project Data Flow
Shared Assets & Queues
Per-Project SDD Index
Next Steps
EOF
      ;;
    rpa-sdd-template.md)
      cat <<'EOF'
Process Overview
Process Map
Detailed Process Steps
Business Rules
Data Definitions
Value Mappings
Exception Handling
Error Handling
Application Inventory
Master Project Architecture
Project Structure
Queue Architecture
Implementation Mode
Packages
Credentials & Assets
Deployment Environment
Testing Strategy
Next Steps
EOF
      ;;
    flow-sdd-template.md)
      cat <<'EOF'
Flow Overview
Flow Diagram
Nodes Inventory
Variables
Subflows
Triggers
Integrated Components
Error Handling
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    bpmn-sdd-template.md)
      cat <<'EOF'
Process Overview
Process Diagram
Pools & Lanes
Activities Inventory
Gateways & Sequence Flows
Events
Data Objects & Variables
Subprocesses & Call Activities
Integrated Components
Error Handling & Retry
Triggers
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    case-sdd-template.md)
      cat <<'EOF'
Case Overview
Case Lifecycle Diagram
Stages
Tasks Grid
Entry / Exit Conditions
Business Rules
Data Definitions
SLA Rules
Escalations
Exception Handling
Compliance Constraints
Roles & RACI Matrix
Task Type Registry
Integrated Components
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    agent-sdd-template.md)
      cat <<'EOF'
Agent Overview
Agent Framework
Tools
Memory / RAG
Evaluation Criteria
Orchestrator Bindings
Error Handling & Escalation
Integrated Components
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    coded-app-sdd-template.md)
      cat <<'EOF'
App Overview
App Type & Tech Stack
Pages & Routes
Components
State Management
API Integration
User Flows
Error Handling
Integrated Components
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    api-workflow-sdd-template.md)
      cat <<'EOF'
API Workflow Overview
Input Schema
Output Schema
Execution Flow
Connectors & External Calls
Error Handling
Project Structure
Testing Strategy
Next Steps
EOF
      ;;
    *)
      return 1 ;;
  esac
}

# ── architecture.json ────────────────────────────────────────────────────────
if [ ! -f "$ARCH_FILE" ]; then
  fail "architecture.json not found: $ARCH_FILE"
  exit 1
fi
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ARCH_FILE" 2>/dev/null; then
  fail "architecture.json is not valid JSON: $ARCH_FILE"
  exit 1
fi

SCOPE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('sdd_scope',''))" "$ARCH_FILE")
# Fall back for a contract written before `solution_name` existed.
# The actual process name, so the naming check below can match THAT rather than a
# shape that any activity type also has.
PROCESS_NAME=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('process_name',''))" "$ARCH_FILE" 2>/dev/null || true)
SOLUTION_NAME=$(python3 - "$ARCH_FILE" <<'EOF_SOLNAME'
import json, sys
d = json.load(open(sys.argv[1]))
n = d.get("solution_name")
if not n:
    base, epic = d.get("process_kebab") or "", d.get("epic_number") or ""
    n = (base + "-" + epic) if base and epic else base
print(n or "")
EOF_SOLNAME
)
TASKS_FILE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('tasks_file',''))" "$ARCH_FILE")
# one "path<TAB>template<TAB>role<TAB>product" line per declared document. The product
# comes from the project that owns the file, falling back to the primary - it is what
# the artifact-vocabulary check keys on.
DECLARED=$(python3 - "$ARCH_FILE" <<'EOF_DECL'
import json, sys
d = json.load(open(sys.argv[1]))
by_path = {}
for p in d.get("projects", []):
    sf = p.get("sdd_file")
    if sf and sf not in by_path:
        by_path[sf] = p.get("product", "")
for f in d.get("sdd_files", []):
    path = f.get("path", "")
    product = by_path.get(path) or d.get("primary_product", "")
    print("\t".join([path, f.get("template", ""), f.get("role", ""), product]))
EOF_DECL
)

if [ -z "$DECLARED" ]; then
  fail "architecture.json declares no sdd_files - nothing to validate."
  exit 1
fi

echo "Validating $(printf '%s\n' "$DECLARED" | grep -c .) SDD file(s) declared by $ARCH_FILE (scope: $SCOPE)"
echo

# ── per-file validation ──────────────────────────────────────────────────────
ALL_SDD_TEXT=$(mktemp)
ROOT_COUNT=0

while IFS=$'\t' read -r SDD TEMPLATE ROLE PRODUCT; do
  [ -n "$SDD" ] || continue
  echo "── $SDD  [$TEMPLATE / $ROLE / ${PRODUCT:-?}]"

  if [ ! -f "$SDD" ]; then
    fail "declared SDD file not found: $SDD"
    echo "Markdown files present in docs/:"
    ls -1 docs/*.md 2>/dev/null || echo "  (none)"
    continue
  fi
  cat "$SDD" >> "$ALL_SDD_TEXT"

  # --- the section contract for this template ------------------------------
  if ! REQUIRED=$(sections_for "$TEMPLATE"); then
    fail "$SDD declares unknown template '$TEMPLATE' - cannot check its sections."
    REQUIRED=""
  fi
  SECTION_COUNT=$(printf '%s\n' "$REQUIRED" | grep -c . || true)

  # --- size, scaled to the template ----------------------------------------
  if [ "$ROLE" = "solution-root" ]; then
    FLOOR="$MIN_ROOT_BYTES"
  else
    FLOOR=$(( ${SECTION_COUNT:-0} * BYTES_PER_SECTION ))
    [ "$FLOOR" -gt 0 ] || FLOOR="$MIN_ROOT_BYTES"
  fi
  BYTES=$(wc -c < "$SDD" | tr -d ' ')
  if [ "$BYTES" -lt "$FLOOR" ]; then
    advise "$SDD is only ${BYTES} bytes (minimum ${FLOOR} for ${SECTION_COUNT} sections) - too thin to build from."
  else
    ok "size ${BYTES} bytes (floor ${FLOOR})"
  fi

  # --- title ---------------------------------------------------------------
  if ! grep -qE '^# Solution Design Document — .+' "$SDD"; then
    fail "$SDD has no '# Solution Design Document — <name>' H1 title."
  else
    ok "H1 title present"
  fi

  # --- planner handoff contract -------------------------------------------
  # Both signals are load-bearing: the downstream planner detects an SDD by
  # either one, and reads only the first ~50 lines to do it.
  if ! grep -qF '<!-- planner-handoff:v1 -->' "$SDD"; then
    fail "$SDD is missing the '<!-- planner-handoff:v1 -->' marker."
  elif [ "$(grep -nF '<!-- planner-handoff:v1 -->' "$SDD" | head -1 | cut -d: -f1)" -gt 50 ]; then
    fail "$SDD has the planner-handoff marker below line 50 - the planner will not see it."
  else
    ok "planner-handoff marker present and early"
  fi

  if ! grep -qxF '## Planner Handoff' "$SDD"; then
    fail "$SDD is missing the exact heading '## Planner Handoff'."
  else
    ok "Planner Handoff heading present"
  fi

  if grep -qiE '^\|[^|]*\*\*Status\*\*[^|]*\|[[:space:]]*draft' "$SDD"; then
    fail "$SDD handoff still says 'Status: draft' - task derivation refuses a draft SDD."
  elif ! grep -qiE '^\|[^|]*\*\*Status\*\*[^|]*\|[[:space:]]*ready' "$SDD"; then
    fail "$SDD handoff has no 'Status | ready' row."
  else
    ok "handoff Status is ready"
  fi

  for field in 'Execution autonomy' 'Delivery model' 'SDD scope' 'Project list section' \
               'Tasks file' 'Generated by' 'Generation date' 'Template validation'; do
    grep -qF "**$field**" "$SDD" || fail "$SDD handoff is missing the '$field' row."
  done
  grep -qiE '\*\*Template validation\*\*[^|]*\|[[:space:]]*passed' "$SDD" \
    || fail "$SDD handoff 'Template validation' is not 'passed'."

  if [ -n "$TASKS_FILE" ] && ! grep -qF "$TASKS_FILE" "$SDD"; then
    fail "$SDD handoff does not name the canonical tasks file '$TASKS_FILE'."
  fi

  # Solution children must point at the root and disclaim independent execution,
  # or task derivation will run twice off the same design.
  case "$ROLE" in
    solution-root)
      ROOT_COUNT=$((ROOT_COUNT + 1))
      grep -qF '**Project SDD role**' "$SDD" \
        || fail "$SDD is the solution root but has no 'Project SDD role' row."
      grep -qiE '\*\*Project SDD role\*\*[^|]*\|[[:space:]]*root' "$SDD" \
        || fail "$SDD is the solution root but its 'Project SDD role' is not 'root'."
      grep -qF '**Solution ID**' "$SDD" || fail "$SDD (root) has no 'Solution ID' row."
      ;;
    project)
      grep -qiE '\*\*Project SDD role\*\*[^|]*\|[[:space:]]*child' "$SDD" \
        || fail "$SDD is a solution project but its 'Project SDD role' is not 'child'."
      grep -qF '**Solution root SDD**' "$SDD" \
        || fail "$SDD (child) does not point at the 'Solution root SDD'."
      grep -qiE '\*\*Independently executable\*\*[^|]*\|[[:space:]]*no' "$SDD" \
        || fail "$SDD (child) is missing 'Independently executable | no'."
      ;;
  esac

  # --- universal front matter ---------------------------------------------
  # Neither a Table of Contents, nor '## Recommended Scope', nor '## Decisions Made'
  # is required any more. All three are generated text that nothing downstream reads,
  # and the last two restate architecture.json - which carries `sdd_scope`,
  # `projects[]`, `blocked_products[]`, `need_profile` and `decisions[]`, and is
  # committed next to the SDD. The record is not lost by dropping them; it just stops
  # being written twice, and every byte not written is a second off the demo clock.
  check_document_history "$SDD"

  # --- numbered sections: present, in order, contiguous, with content -----
  SECTION_FAILS=0
  N=0
  while IFS= read -r section; do
    [ -n "$section" ] || continue
    N=$((N + 1))
    # Tolerate either '## 7. Name' or '## Name'; the generator writes numbered.
    if ! grep -qE "^## ([0-9]+\. )?$(printf '%s' "$section" | sed 's/[][\\.*^$]/\\&/g')$" "$SDD"; then
      fail "$SDD is missing section '$section' (template $TEMPLATE)."
      SECTION_FAILS=$((SECTION_FAILS + 1))
      continue
    fi
    CONTENT=$(awk -v want="$section" '
      $0 ~ "^## ([0-9]+\\. )?"want"$" { inside = 1; next }
      inside && /^## / { exit }
      inside && NF && !/^<!--/ { print }
    ' "$SDD" | wc -l | tr -d ' ')
    if [ "${CONTENT:-0}" -lt 2 ]; then
      fail "$SDD section '$section' is empty or has only one line of content."
      SECTION_FAILS=$((SECTION_FAILS + 1))
    fi
  done <<< "$REQUIRED"
  [ "$SECTION_FAILS" -eq 0 ] && [ "$N" -gt 0 ] && ok "all $N template sections present with content"

  ORDER=$(grep -oE '^## [0-9]+\.' "$SDD" | grep -oE '[0-9]+')
  if [ -n "$ORDER" ]; then
    if [ "$(echo "$ORDER" | tr '\n' ' ')" != "$(echo "$ORDER" | sort -n | tr '\n' ' ')" ]; then
      fail "$SDD numbered sections are out of order: $(echo "$ORDER" | tr '\n' ' ')"
    else
      ok "sections in order"
    fi
    EXPECTED=$(seq 1 "$(echo "$ORDER" | wc -l | tr -d ' ')" | tr '\n' ' ')
    if [ "$(echo "$ORDER" | tr '\n' ' ')" != "$EXPECTED" ]; then
      fail "$SDD section numbering is not contiguous from 1: got $(echo "$ORDER" | tr '\n' ' ')"
    fi
    LAST=$(grep -E '^## [0-9]+\.' "$SDD" | tail -1)
    case "$LAST" in
      *"Next Steps") ok "document ends on Next Steps" ;;
      *) fail "$SDD last numbered section is '$LAST' - an SDD must end on 'Next Steps'." ;;
    esac
  fi

  # --- unfilled template scaffolding --------------------------------------
  # Angle-bracket tokens and pipe-alternative stubs are what a half-filled
  # template looks like. The one legitimate angle bracket is the DO NOT RENAME /
  # planner-handoff comment pair.
  if LEFTOVERS=$(grep -nE '<[A-Z][A-Z0-9_]{2,}>|<placeholder|<one-line|<PATH_TO|<draft |<autonomous |<cloud |<single-product |<its own filename|<SOLUTION_NAME|<PROJECT_NAME|<PROCESS_NAME|<AGENT_NAME|<APP_NAME|<STAGE_NAME|<FLOW_NAME|<MAPPING_NAME|<DATE>|<AUTHOR>|<VERSION' "$SDD"); then
    fail "$SDD has unfilled template placeholders:"
    echo "$LEFTOVERS" | head -20
  else
    ok "no template placeholders"
  fi

  if LEFTOVERS=$(grep -nEi '(\bTBD\b|Lorem ipsum|\bTODO\b|\bFIXME\b|\bX{4,}\b|EMIT THIS BLOCK|Phase 2 sections:|Before filling §)' "$SDD"); then
    fail "$SDD has placeholder or template-instruction text left in it:"
    echo "$LEFTOVERS" | head -20
  else
    ok "no leftover instructions"
  fi

  # --- tables have data rows ----------------------------------------------
  EMPTY_TABLES=$(awk '
    /^\|[ :|-]+\|[ :|-]*$/ { sep = NR; next }
    sep && NR == sep + 1 && $0 !~ /^\|/ { print sep; sep = 0; next }
    sep && NR == sep + 1 { sep = 0 }
  ' "$SDD")
  if [ -n "$EMPTY_TABLES" ]; then
    fail "$SDD has empty table(s) - header with no data rows, at line(s): $(echo "$EMPTY_TABLES" | tr '\n' ' ')"
  else
    ok "all tables have data rows"
  fi

  # --- an SDD is architecture, not a plan ---------------------------------
  # Task derivation belongs to the next stage; a task list here gets built twice.
  if PLAN=$(grep -nE '^#+ *(Implementation Plan|Task List|Tasks)$|^#+ *Task [0-9]+|TaskCreate' "$SDD"); then
    fail "$SDD contains a task list - an SDD is architecture only:"
    echo "$PLAN" | head -10
  else
    ok "no task list"
  fi

  # --- artifact vocabulary ------------------------------------------------
  # The template being right does not mean the content is. An agent that defaults to
  # XAML writes an RPA design under an API Workflow heading - internally
  # contradictory, and the build agent then has nothing real to follow. Advisory:
  # it drives a repair pass but never blocks the run.
  # The solution root indexes projects rather than specifying artifacts, so it has no
  # vocabulary of its own and is skipped.
  if [ "$ROLE" != "solution-root" ] && [ -n "${PRODUCT:-}" ]; then
    case "$PRODUCT" in
      api-workflows)   V_MUST='Workflow\.json|uipath\.json'; V_NOT='\.xaml|project\.json' ;;
      rpa-*)           V_MUST='project\.json';                V_NOT='Workflow\.json|caseplan\.json|agent\.json' ;;
      maestro-flow)    V_MUST='\.flow';                       V_NOT='\.xaml' ;;
      maestro-bpmn)    V_MUST='\.bpmn';                       V_NOT='\.xaml' ;;
      case-management) V_MUST='caseplan\.json';               V_NOT='\.xaml' ;;
      agents)          V_MUST='agent\.json';                  V_NOT='\.xaml' ;;
      coded-apps)      V_MUST='package\.json';                V_NOT='\.xaml' ;;
      *)               V_MUST=''; V_NOT='' ;;
    esac

    if [ -n "$V_MUST" ]; then
      if grep -qE "$V_MUST" "$SDD"; then
        ok "names its own '$PRODUCT' artifacts"
      else
        advise "$SDD is a '$PRODUCT' design but never names its own artifacts (expected something matching $V_MUST) - the content does not match the product."
      fi
    fi

    if [ -n "$V_NOT" ]; then
      V_HITS=$(grep -cE "$V_NOT" "$SDD" || true)
      if [ "${V_HITS:-0}" -gt 0 ]; then
        advise "$SDD is a '$PRODUCT' design but has ${V_HITS} line(s) referencing another product's artifacts ($V_NOT):"
        grep -nE "$V_NOT" "$SDD" | head -5
      else
        ok "no foreign artifact references"
      fi
    fi
  fi

  # --- review marker ------------------------------------------------------
  # An SDD's open questions go to an architect; the PDD owns the SME-facing ones.
  # A document carrying the wrong marker is one nobody is assigned to answer.
  if grep -qF '[SME REVIEW]' "$SDD"; then
    advise "$SDD uses [SME REVIEW]; an SDD's open items are [ARCHITECT REVIEW] ($(grep -cF '[SME REVIEW]' "$SDD") occurrence(s))."
  fi

  # --- resource naming ----------------------------------------------------
  # Names come from the repository's epic key, never from the process name.
  #
  # There is deliberately NO "the epic prefix must appear N times" check here.
  # It counted lines containing the prefix string, not resources, so a design that
  # legitimately owns nothing - all headless API calls over pre-existing shared IS
  # connections, which must never be renamed - could not pass it honestly. It also
  # counted an open question ASKING what the epic key should be as a hit. The only
  # way through was an agent padding the document with the prefix to move a counter,
  # which cost a repair round-trip and taught the next stage nothing. Nothing
  # downstream reads the prefix; the convention is stated in the architect prompt,
  # where it belongs.
  if [ -n "$RESOURCE_PREFIX" ] && [ "$ROLE" != "solution-root" ]; then
    # The old convention: a resource named <ProcessName>_<thing>. Not unique across
    # the estate, and it changes whenever the process is renamed.
    #
    # Matched against the ACTUAL process name from the contract, never against a
    # shape. The previous pattern was \b[A-Z][a-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b,
    # which matches every PascalCase token containing an underscore - so it flagged
    # `Do_While`, `Try_Catch`, `HTTP_Request` and `If_1`, all of which are UiPath
    # activity types and none of which is a resource. One of those cost a repair
    # pass that tried to rename the activity type `jactiv_737_Do_While`.
    BADNAMES=""
    if [ -n "${PROCESS_NAME:-}" ]; then
      BADNAMES=$(grep -oE "\b${PROCESS_NAME}_[A-Za-z0-9_]+\b" "$SDD" | sort -u || true)
    fi
    if [ -n "$BADNAMES" ]; then
      advise "$SDD has process-name-prefixed resource name(s) - use '${RESOURCE_PREFIX}<thing>' instead:"
      printf '%s\n' "$BADNAMES" | head -6 | sed 's/^/    /'
    fi
  fi

  # The solution name is architecture.json's `solution_name` - deployment packs the
  # package under it AND names the Orchestrator sub-folder after it.
  if [ "$ROLE" = "solution-root" ] && [ -n "$SOLUTION_NAME" ] && ! grep -qF "$SOLUTION_NAME" "$SDD"; then
    advise "$SDD is the solution root but never names the solution '$SOLUTION_NAME' (architecture.json solution_name)."
  fi

  # --- the sections development actually needs ----------------------------
  if [ "$ROLE" != "solution-root" ]; then
    TEST_SUBS=$(awk '
      /^## ([0-9]+\. )?Testing Strategy$/ { inside = 1; next }
      inside && /^## / { exit }
      inside && /^### / { n++ }
      END { print n + 0 }
    ' "$SDD")
    if [ "$TEST_SUBS" -lt 3 ]; then
      advise "$SDD Testing Strategy has only ${TEST_SUBS} subsection(s) - needs happy path, exceptions, system errors and acceptance criteria."
    else
      ok "Testing Strategy has ${TEST_SUBS} subsections"
    fi

    STRUCT_ROWS=$(awk '
      /^## ([0-9]+\. )?Project Structure$/ { inside = 1; next }
      inside && /^## / { exit }
      inside && NF { n++ }
      END { print n + 0 }
    ' "$SDD")
    if [ "$STRUCT_ROWS" -lt 10 ]; then
      advise "$SDD Project Structure has only ${STRUCT_ROWS} lines - a developer cannot lay the project out from that."
    else
      ok "Project Structure has ${STRUCT_ROWS} lines"
    fi
  fi
  echo
done <<< "$DECLARED"

# ── solution-scope consistency ───────────────────────────────────────────────
case "$SCOPE" in
  solution)
    if [ "$ROOT_COUNT" -ne 1 ]; then
      fail "solution scope needs exactly one solution-root SDD, found ${ROOT_COUNT}."
    else
      ok "exactly one solution root"
    fi
    ;;
  single-product)
    [ "$ROOT_COUNT" -eq 0 ] || fail "single-product scope must not declare a solution-root SDD."
    ;;
esac

# ── traceability against the PDD ─────────────────────────────────────────────
# A rule the business stated and the design never mentions is the failure mode
# that costs a rebuild, so business rules are a hard gate. Exception and error IDs
# are a warning: a design may legitimately restructure those tables.
if [ "${#PDD_FILES[@]}" -gt 0 ]; then
  echo "── traceability"
  for pdd in "${PDD_FILES[@]}"; do
    [ -f "$pdd" ] || { warn "PDD not found for traceability: $pdd"; continue; }

    # IDs taken from the FIRST column of the PDD's Business Rules table only. A bare
    # grep for BR-<digits> also catches the `Source` cells, where the PDD correctly
    # quotes the SME document's own numbering (BR-001 ...) - and then demands the SDD
    # carry those too. That is how one rule became two: the SDD grew a "PDD source ID"
    # column to satisfy this grep, the DSD validator then read BOTH forms out of the
    # SDD and demanded both, and a 10-rule design was reported as "all 20 BR-xx rules
    # accounted for". Canonical IDs only.
    PDD_BR=$(python3 - "$pdd" <<'EOF_BR'
import re, sys
want, out = False, []
for line in open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines():
    if re.match(r"^## \d+\. Business Rules\s*$", line):
        want = True
        continue
    if want and line.startswith("## "):
        break
    if want and line.startswith("|"):
        cell = re.sub("[" + chr(96) + r"*\s]", "", line.strip("|").split("|")[0])
        if re.fullmatch(r"BR-\d+", cell):
            out.append(cell)
print("\n".join(sorted(set(out))))
EOF_BR
)
    MISSING_BR=""
    for id in $PDD_BR; do
      grep -qF "$id" "$ALL_SDD_TEXT" || MISSING_BR="$MISSING_BR $id"
    done
    if [ -n "$MISSING_BR" ]; then
      advise "business rules from $pdd have no home in the design:$MISSING_BR"
    else
      ok "every BR-xx in $(basename "$pdd") is referenced in the design"
    fi

    # IDs taken from the first column of the PDD's exception / error tables only,
    # so a stray "B1" in prose cannot create a false failure.
    IDS=$(python3 - "$pdd" <<'EOF_IDS'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
want, out = False, []
for line in text:
    if re.match(r"^## \d+\. (Business Exceptions|System Errors)\s*$", line):
        want = True
        continue
    if want and line.startswith("## "):
        want = False
    if want and line.startswith("|"):
        cell = re.sub("[" + chr(96) + r"*\s]", "", line.strip("|").split("|")[0])
        if re.fullmatch(r"[BS]\d+", cell):
            out.append(cell)
print(" ".join(sorted(set(out))))
EOF_IDS
)
    MISSING_IDS=""
    for id in $IDS; do
      grep -qE "\b$id\b" "$ALL_SDD_TEXT" || MISSING_IDS="$MISSING_IDS $id"
    done
    if [ -n "$MISSING_IDS" ]; then
      warn "exception/error IDs from $pdd are not referenced in the design (renamed, or dropped?):$MISSING_IDS"
    elif [ -n "$IDS" ]; then
      ok "every exception/error ID in $(basename "$pdd") is referenced"
    fi
  done
  echo
fi

rm -f "$ALL_SDD_TEXT"

[ "$WARNINGS" -gt 0 ] && echo "SDD validation raised ${WARNINGS} warning(s)."

# ── exit code ────────────────────────────────────────────────────────────────
# The exit code exists to DRIVE the repair pass, not to reject a document. The
# workflow never lets it fail the run: the Validate step is continue-on-error and
# the Verify step captures the status instead of propagating it, so the SDD is
# committed and the PR opens whatever this says.
#
# SDD_NEVER_FAIL=1 makes that guarantee at the script level too, for a caller that
# cannot conveniently trap the status - findings are still printed and still
# annotate the run, but the exit is always 0. Leave it UNSET for the repair loop,
# which needs a non-zero exit to know there is work to do.
if [ "$FAILURES" -gt 0 ]; then
  echo "SDD validation found ${FAILURES} blocking problem(s)$([ "$ADVISORIES" -gt 0 ] && echo " and ${ADVISORIES} quality problem(s)")."
  [ "${SDD_NEVER_FAIL:-0}" = "1" ] && { echo "SDD_NEVER_FAIL=1 - reporting only."; exit 0; }
  exit 1
fi
# Advisories do NOT trigger the repair, and calling them advisory while exiting 1
# was the bug behind a whole class of wasted runs. A repair pass costs about
# forty-five seconds - a fresh agent, its own action setup, its own re-read of the
# document - and it must be spent only on something that stops the automation
# being built. Style, naming conventions, section counts and marker spelling do
# not. The worst case was a check that matched any PascalCase_token and flagged
# `Do_While`, a UiPath activity type, as a badly named resource: validation failed,
# a repair agent started, and its first edit renamed it `jactiv_737_Do_While`.
#
# So: `fail` blocks and repairs, `advise` prints a warning and the run continues.
# If a new check would stop the demo when it fires, it is a `fail`. If it would
# only make someone tidy prose, it is an `advise` - and now that is free.
if [ "$ADVISORIES" -gt 0 ]; then
  echo "SDD validation passed with ${ADVISORIES} advisory finding(s) - printed above, not repaired."
  exit 0
fi
echo "SDD validation passed."
