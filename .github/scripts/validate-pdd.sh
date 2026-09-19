#!/usr/bin/env bash
# Validates that a generated PDD is complete enough to feed the SDD stage.
# Reports every problem it finds (not just the first) and exits 1 if any.
#
# Usage: .github/scripts/validate-pdd.sh docs/pdd-analysis-JACTIV-572.md
set -uo pipefail

PDD_FILE="${1:?usage: validate-pdd.sh <path-to-pdd.md>}"
MIN_BYTES="${MIN_PDD_BYTES:-4000}"
FAILURES=0

fail() { echo "::error::$*"; FAILURES=$((FAILURES + 1)); }
ok()   { echo "  ok  - $*"; }

REQUIRED_SECTIONS=(
  "1. Document Control"
  "2. Introduction"
  "3. Process Overview"
  "4. Scope"
  "5. As-Is Process"
  "6. To-Be Process (High Level)"
  "7. Detailed Process Steps"
  "8. Applications and Systems"
  "9. Business Rules"
  "10. Business Exceptions"
  "11. System Errors"
  "12. Data Definitions"
  "13. Environment and Constraint Signals"
  "14. Reporting Requirements"
  "15. Canonical Test Data"
  "16. Decomposition Signals"
  "17. Assumptions, Dependencies and Open Questions"
  "18. Benefits and Success Criteria"
)

echo "Validating $PDD_FILE"

# --- exists and non-trivial ------------------------------------------------
if [ ! -f "$PDD_FILE" ]; then
  fail "PDD file not found: $PDD_FILE"
  echo "Markdown files present:"
  find . -name '*.md' -not -path './.git/*' || true
  exit 1
fi

BYTES=$(wc -c < "$PDD_FILE" | tr -d ' ')
if [ "$BYTES" -lt "$MIN_BYTES" ]; then
  fail "PDD is only ${BYTES} bytes (minimum ${MIN_BYTES}) - the document is too thin to be a real PDD."
else
  ok "size ${BYTES} bytes"
fi

# --- title -----------------------------------------------------------------
if ! grep -q '^# ' "$PDD_FILE"; then
  fail "No H1 title line (expected '# PDD - <process title>')."
else
  ok "H1 title present"
fi

# --- every required section present, with content --------------------------
SECTION_FAILS=0
for section in "${REQUIRED_SECTIONS[@]}"; do
  if ! grep -qxF "## $section" "$PDD_FILE"; then
    fail "Missing section heading: '## $section'"
    SECTION_FAILS=$((SECTION_FAILS + 1))
    continue
  fi
  # count non-blank, non-heading lines until the next '## ' heading
  CONTENT=$(awk -v want="## $section" '
    $0 == want { inside = 1; next }
    inside && /^## / { exit }
    inside && NF { print }
  ' "$PDD_FILE" | wc -l | tr -d ' ')
  if [ "${CONTENT:-0}" -lt 2 ]; then
    fail "Section '$section' is empty or has only one line of content."
    SECTION_FAILS=$((SECTION_FAILS + 1))
  fi
done
[ "$SECTION_FAILS" -eq 0 ] && ok "all ${#REQUIRED_SECTIONS[@]} sections present with content"

# --- sections in order -----------------------------------------------------
ORDER=$(grep -oE '^## [0-9]+\.' "$PDD_FILE" | grep -oE '[0-9]+')
if [ "$(echo "$ORDER" | tr '\n' ' ')" != "$(echo "$ORDER" | sort -n | tr '\n' ' ')" ]; then
  fail "Numbered sections are out of order: $(echo "$ORDER" | tr '\n' ' ')"
else
  ok "sections in order"
fi

# --- no template leftovers -------------------------------------------------
if LEFTOVERS=$(grep -nEi '(\bTBD\b|Lorem ipsum|<placeholder|<one-line|<process title>|\bTODO\b|\bFIXME\b|XXXX)' "$PDD_FILE"); then
  fail "Placeholder / template text left in the PDD:"
  echo "$LEFTOVERS" | head -20
else
  ok "no placeholder text"
fi

# --- tables have data rows -------------------------------------------------
# A separator row (|---|---|) must be followed by at least one data row.
EMPTY_TABLES=$(awk '
  /^\|[ :|-]+\|[ :|-]*$/ { sep = NR; next }
  sep && NR == sep + 1 && $0 !~ /^\|/ { print sep; sep = 0; next }
  sep && NR == sep + 1 { sep = 0 }
' "$PDD_FILE")
if [ -n "$EMPTY_TABLES" ]; then
  fail "Empty table(s) - header with no data rows, at line(s): $(echo "$EMPTY_TABLES" | tr '\n' ' ')"
else
  ok "all tables have data rows"
fi

# --- detailed process steps must actually be detailed ----------------------
STEP_ROWS=$(awk '
  $0 == "## 7. Detailed Process Steps" { inside = 1; next }
  inside && /^## / { exit }
  inside && /^\|/ && $0 !~ /^\|[ :|-]+\|[ :|-]*$/ { n++ }
  END { print n + 0 }
' "$PDD_FILE")
if [ "$STEP_ROWS" -lt 5 ]; then
  fail "Section 7 has only ${STEP_ROWS} table rows - needs a real step-by-step breakdown (header + at least 4 steps)."
else
  ok "section 7 has ${STEP_ROWS} table rows"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "PDD validation FAILED with ${FAILURES} problem(s)."
  exit 1
fi
echo "PDD validation passed."
