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
FAILURES=0
WARNINGS=0

fail() { echo "::error::$*"; FAILURES=$((FAILURES + 1)); }
warn() { echo "::warning::$*"; WARNINGS=$((WARNINGS + 1)); }
ok()   { echo "  ok  - $*"; }

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
Performance & Scaling
Security & Authentication
Consumers
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
TASKS_FILE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('tasks_file',''))" "$ARCH_FILE")
# one "path<TAB>template<TAB>role" line per declared document
DECLARED=$(python3 - "$ARCH_FILE" <<'EOF_DECL'
import json, sys
for f in json.load(open(sys.argv[1])).get("sdd_files", []):
    print("\t".join([f.get("path", ""), f.get("template", ""), f.get("role", "")]))
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

while IFS=$'\t' read -r SDD TEMPLATE ROLE; do
  [ -n "$SDD" ] || continue
  echo "── $SDD  [$TEMPLATE / $ROLE]"

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
    fail "$SDD is only ${BYTES} bytes (minimum ${FLOOR} for ${SECTION_COUNT} sections) - too thin to build from."
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
  for h in '## Document History' '## Recommended Scope' '## Table of Contents'; do
    grep -qxF "$h" "$SDD" || fail "$SDD is missing '$h'."
  done
  # Autonomous generation has no human checkpoint, so the record of what was
  # picked and why is mandatory rather than optional.
  grep -qxF '## Decisions Made' "$SDD" \
    || fail "$SDD is missing '## Decisions Made' - this run had no human checkpoint."

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

  if LEFTOVERS=$(grep -nEi '(\bTBD\b|Lorem ipsum|\bTODO\b|\bFIXME\b|XXXX|EMIT THIS BLOCK|Phase 2 sections:|Before filling §)' "$SDD"); then
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

  # --- the sections development actually needs ----------------------------
  if [ "$ROLE" != "solution-root" ]; then
    TEST_SUBS=$(awk '
      /^## ([0-9]+\. )?Testing Strategy$/ { inside = 1; next }
      inside && /^## / { exit }
      inside && /^### / { n++ }
      END { print n + 0 }
    ' "$SDD")
    if [ "$TEST_SUBS" -lt 3 ]; then
      fail "$SDD Testing Strategy has only ${TEST_SUBS} subsection(s) - needs happy path, exceptions, system errors and acceptance criteria."
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
      fail "$SDD Project Structure has only ${STRUCT_ROWS} lines - a developer cannot lay the project out from that."
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

    MISSING_BR=""
    for id in $(grep -oE '\bBR-[0-9]+\b' "$pdd" | sort -u); do
      grep -qF "$id" "$ALL_SDD_TEXT" || MISSING_BR="$MISSING_BR $id"
    done
    if [ -n "$MISSING_BR" ]; then
      fail "business rules from $pdd have no home in the design:$MISSING_BR"
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

if [ "$WARNINGS" -gt 0 ]; then
  echo "SDD validation raised ${WARNINGS} warning(s)."
fi
if [ "$FAILURES" -gt 0 ]; then
  echo "SDD validation FAILED with ${FAILURES} problem(s)."
  exit 1
fi
echo "SDD validation passed."
