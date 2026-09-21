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
# Advisory: printed and annotated, never counted toward the exit code.
soft_note() { echo "::warning::[advisory] $*"; }

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

REQUIRED_SECTIONS=(
  "1. Document Control"
  "2. Introduction"
  "3. Process Overview"
  "4. Scope"
  "5. To-Be Process (High Level)"
  "6. Detailed Process Steps"
  "7. Applications and Systems"
  "8. Business Rules"
  "9. Business Exceptions"
  "10. System Errors"
  "11. Data Definitions"
  "12. Environment and Constraint Signals"
  "13. Canonical Test Data"
  "14. Decomposition Signals"
  "15. Assumptions, Dependencies and Open Questions"
  "16. Success Criteria"
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

# --- document history ------------------------------------------------------
check_document_history "$PDD_FILE" "PDD"

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

# --- business rule IDs use ONE format --------------------------------------
# Every downstream stage (SDD, DSD, review) matches rule IDs as exact strings, so
# BR-01 and BR-001 are two different rules to all of them. The ID column of
# section 8 is the authority, and it is the only place this check can fail:
# a PDD traces every rule back to the SME document, and that document numbers its
# own rules (BR-001 ...). Those citations belong in `Source` cells and are correct
# there. Failing the build over them buys nothing and costs a repair round-trip
# that rewrites real citations into references the source document does not have.
BR_CANON=$(awk '
  $0 == "## 8. Business Rules" { inside = 1; next }
  inside && /^## / { exit }
  inside && /^\|/ && $0 !~ /^\|[ :|-]+\|[ :|-]*$/ {
    n = split($0, cell, "|")
    id = cell[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
    if (id ~ /^BR-[0-9]+$/) print id
  }
' "$PDD_FILE" | sort -u)

if [ -z "$BR_CANON" ]; then
  fail "Section 8 has no row whose first column is a BR-nn rule ID - the SDD reads that column as the rule list."
else
  BR_WIDTHS=$(printf '%s\n' "$BR_CANON" | sed 's/^BR-//' | awk '{ print length($0) }' | sort -u)
  BR_NWIDTH=$(printf '%s\n' "$BR_WIDTHS" | grep -c . || true)
  if [ "${BR_NWIDTH:-0}" -gt 1 ]; then
    fail "Section 8 rule IDs mix digit widths ($(printf '%s' "$BR_WIDTHS" | tr '\n' '/' | sed 's:/$::')) - use one zero-padded width, BR-01 .. BR-nn."
    echo "    ids found: $(printf '%s' "$BR_CANON" | tr '\n' ' ')"
  else
    ok "section 8 rule IDs use one format ($(printf '%s\n' "$BR_CANON" | grep -c . || true) rules)"
  fi

  # Rule IDs mentioned anywhere else should resolve to that column, otherwise the
  # SDD hunts for a rule that does not exist. Advisory only: `Source` cells are
  # already excluded, so what is left is prose the next revision can tidy - not a
  # reason to spend a minute of agent time re-running the document.
  BR_REFS=$(awk '
    /^\|/ {
      if (!intable) { intable = 1; hdr = 0; split("", skip) }  # split() clears: portable to mawk
      if ($0 ~ /^\|[ :|-]+\|[ :|-]*$/) next
      n = split($0, cell, "|")
      if (!hdr) {
        hdr = 1
        for (i = 2; i < n; i++) {
          t = tolower(cell[i]); gsub(/^[ \t]+|[ \t]+$/, "", t)
          if (t ~ /source|traceab|reference/) skip[i] = 1
        }
        next
      }
      for (i = 2; i < n; i++) if (!(i in skip)) print cell[i]
      next
    }
    { intable = 0; print }
  ' "$PDD_FILE" | grep -oE '\bBR-[0-9]+\b' | sort -u || true)

  BR_DANGLING=""
  for ref in $BR_REFS; do
    printf '%s\n' "$BR_CANON" | grep -qxF "$ref" || BR_DANGLING="$BR_DANGLING $ref"
  done
  if [ -n "$BR_DANGLING" ]; then
    soft_note "Rule references outside section 8 that are not in its ID column:${BR_DANGLING} - downstream stages resolve rule IDs against that column only. If these are the SME document's own numbers, they belong in a 'Source' cell."
  else
    ok "all rule references resolve to section 8"
  fi
fi

# --- no template leftovers -------------------------------------------------
if LEFTOVERS=$(grep -nEi '(\bTBD\b|Lorem ipsum|<placeholder|<one-line|<process title>|\bTODO\b|\bFIXME\b|\bX{4,}\b)' "$PDD_FILE"); then
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
  $0 == "## 6. Detailed Process Steps" { inside = 1; next }
  inside && /^## / { exit }
  inside && /^\|/ && $0 !~ /^\|[ :|-]+\|[ :|-]*$/ { n++ }
  END { print n + 0 }
' "$PDD_FILE")
if [ "$STEP_ROWS" -lt 5 ]; then
  fail "Section 6 has only ${STEP_ROWS} table rows - needs a real step-by-step breakdown (header + at least 4 steps)."
else
  ok "section 6 has ${STEP_ROWS} table rows"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "PDD validation FAILED with ${FAILURES} problem(s)."
  exit 1
fi
echo "PDD validation passed."
