#!/usr/bin/env bash
# Validates that the generated DSD(s) are honest AS-BUILT documentation.
# Reports every problem it finds (not just the first) and exits 1 if any.
#
# Usage: .github/scripts/validate-dsd.sh <architecture.json>
#
# Docs runs AFTER Development, so the DSD documents the delivered code rather than
# specifying work to come. The check that makes that real is the code-reference test:
# every `code/...` path the document names must exist on disk. A DSD that describes
# the design instead of the delivery fails it, which is the exact failure mode of an
# agent that read the SDD and paraphrased it.
#
# The DSD paths are derived from architecture.json exactly as uipath-dsd.yml derives
# them, so the validator and the workflow cannot disagree about which files exist.
set -uo pipefail

ARCH_FILE="${1:?usage: validate-dsd.sh <architecture.json>}"

# 600, not 700: as-built sections are largely tables (config, rules, troubleshooting)
# and are legitimately more compact than the build-spec prose this stage used to hold.
BYTES_PER_SECTION="${MIN_DSD_BYTES_PER_SECTION:-600}"
CODE_DIR="${CODE_DIR:-code}"
FAILURES=0
WARNINGS=0

fail() { echo "::error::$*"; FAILURES=$((FAILURES + 1)); }
warn() { echo "::warning::$*"; WARNINGS=$((WARNINGS + 1)); }
ok()   { echo "  ok  - $*"; }

# ── the section contract ─────────────────────────────────────────────────────
# Kept in sync with the section list in uipath-dsd.yml's agent prompt.
REQUIRED_SECTIONS=(
  "Solution Overview"
  "As-Built Architecture"
  "Component Reference"
  "Data and Interface Reference"
  "Configuration Reference"
  "Business Rules Implemented"
  "Exception and Error Handling"
  "Operations Runbook"
  "Troubleshooting Guide"
  "Monitoring and Logging"
  "Deviations from Design"
  "Handover and Support"
)
SECTION_COUNT=${#REQUIRED_SECTIONS[@]}
FLOOR=$(( SECTION_COUNT * BYTES_PER_SECTION ))

# ── architecture.json ────────────────────────────────────────────────────────
if [ ! -f "$ARCH_FILE" ]; then
  fail "architecture.json not found: $ARCH_FILE"
  exit 1
fi
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ARCH_FILE" 2>/dev/null; then
  fail "architecture.json is not valid JSON: $ARCH_FILE"
  exit 1
fi

DECLARED=$(python3 - "$ARCH_FILE" <<'EOF_PLAN'
import json, sys
d = json.load(open(sys.argv[1]))
rows, seen = [], set()
for p in sorted(d["projects"], key=lambda x: x.get("build_order", 99)):
    if p.get("role") == "component":
        continue
    kebab = p.get("kebab") or p["name"].lower().replace(".", "-")
    sdd = p.get("sdd_file", "")
    key = sdd or kebab
    if key in seen:
        continue
    seen.add(key)
    path = (f"docs/{d['process_kebab']}-dsd.md" if d["sdd_scope"] == "single-product"
            else f"docs/{kebab}-dsd.md")
    rows.append("\t".join([path, sdd, p.get("product", ""), p.get("skill", ""), p["name"]]))
print("\n".join(rows))
EOF_PLAN
)

if [ -z "$DECLARED" ]; then
  fail "architecture.json yields no buildable project - no DSD is expected, which is itself wrong."
  exit 1
fi

echo "Validating $(printf '%s\n' "$DECLARED" | grep -c .) as-built DSD file(s) derived from $ARCH_FILE"
echo "Section floor: ${SECTION_COUNT} sections x ${BYTES_PER_SECTION} bytes = ${FLOOR}"
echo

while IFS=$'\t' read -r DSD SDD PRODUCT SKILL PROJECT; do
  [ -n "$DSD" ] || continue
  echo "── $DSD  [$PROJECT / $PRODUCT]"

  if [ ! -f "$DSD" ]; then
    fail "declared DSD file not found: $DSD"
    ls -1 docs/*.md 2>/dev/null || echo "  (no docs/*.md)"
    echo
    continue
  fi

  # --- size ----------------------------------------------------------------
  BYTES=$(wc -c < "$DSD" | tr -d ' ')
  if [ "$BYTES" -lt "$FLOOR" ]; then
    fail "$DSD is only ${BYTES} bytes (minimum ${FLOOR}) - not usable documentation."
  else
    ok "size ${BYTES} bytes"
  fi

  # --- title and document control -----------------------------------------
  grep -qE '^# Detailed Solution Design — .+' "$DSD" \
    || fail "$DSD has no '# Detailed Solution Design — <name>' H1 title."

  if ! grep -qF '<!-- dsd-handoff:v1 -->' "$DSD"; then
    fail "$DSD is missing the '<!-- dsd-handoff:v1 -->' marker."
  elif [ "$(grep -nF '<!-- dsd-handoff:v1 -->' "$DSD" | head -1 | cut -d: -f1)" -gt 50 ]; then
    fail "$DSD has the dsd-handoff marker below line 50."
  else
    ok "dsd-handoff marker present and early"
  fi

  grep -qxF '## Document Control' "$DSD" \
    || fail "$DSD is missing the exact heading '## Document Control'."

  if grep -qiE '\*\*Status\*\*[^|]*\|[[:space:]]*draft' "$DSD"; then
    fail "$DSD says 'Status: draft' - the release gate reads this document."
  elif ! grep -qiE '\*\*Status\*\*[^|]*\|[[:space:]]*ready' "$DSD"; then
    fail "$DSD has no 'Status | ready' row."
  else
    ok "Status is ready"
  fi

  grep -qiE '\*\*Documents\*\*[^|]*\|[[:space:]]*as-built' "$DSD" \
    || fail "$DSD does not declare '| **Documents** | as-built |' - this stage documents the delivery, not the design."

  for field in 'Source SDD' 'Source architecture' 'Project' 'Product' 'Build skill' \
               'Generated by' 'Generation date'; do
    grep -qF "**$field**" "$DSD" || fail "$DSD Document Control is missing the '$field' row."
  done

  if [ -n "$SDD" ] && ! grep -qF "$SDD" "$DSD"; then
    fail "$DSD does not name the SDD '$SDD' it is measured against."
  fi

  for h in '## Document History' '## Table of Contents'; do
    grep -qxF "$h" "$DSD" || fail "$DSD is missing '$h'."
  done

  # --- numbered sections: present, in order, contiguous, with content -----
  SECTION_FAILS=0
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qE "^## ([0-9]+\. )?$(printf '%s' "$section" | sed 's/[][\\.*^$]/\\&/g')$" "$DSD"; then
      fail "$DSD is missing section '$section'."
      SECTION_FAILS=$((SECTION_FAILS + 1))
      continue
    fi
    CONTENT=$(awk -v want="$section" '
      $0 ~ "^## ([0-9]+\\. )?"want"$" { inside = 1; next }
      inside && /^## / { exit }
      inside && NF && !/^<!--/ { print }
    ' "$DSD" | wc -l | tr -d ' ')
    if [ "${CONTENT:-0}" -lt 2 ]; then
      fail "$DSD section '$section' is empty or has only one line of content."
      SECTION_FAILS=$((SECTION_FAILS + 1))
    fi
  done
  [ "$SECTION_FAILS" -eq 0 ] && ok "all ${SECTION_COUNT} sections present with content"

  ORDER=$(grep -oE '^## [0-9]+\.' "$DSD" | grep -oE '[0-9]+')
  if [ -n "$ORDER" ]; then
    [ "$(echo "$ORDER" | tr '\n' ' ')" = "$(echo "$ORDER" | sort -n | tr '\n' ' ')" ] \
      || fail "$DSD numbered sections are out of order: $(echo "$ORDER" | tr '\n' ' ')"
    EXPECTED=$(seq 1 "$(echo "$ORDER" | wc -l | tr -d ' ')" | tr '\n' ' ')
    [ "$(echo "$ORDER" | tr '\n' ' ')" = "$EXPECTED" ] \
      || fail "$DSD section numbering is not contiguous from 1: got $(echo "$ORDER" | tr '\n' ' ')"
    LAST=$(grep -E '^## [0-9]+\.' "$DSD" | tail -1)
    case "$LAST" in
      *"Handover and Support") ok "document ends on Handover and Support" ;;
      *) fail "$DSD last numbered section is '$LAST' - a DSD must end on 'Handover and Support'." ;;
    esac
  fi

  # ── the as-built test ───────────────────────────────────────────────────
  # Every code path the document names must exist. This is what separates
  # documentation of the delivery from a paraphrase of the design.
  REFS=$(grep -oE '`'"$CODE_DIR"'/[^`]+`' "$DSD" | tr -d '`' | sort -u || true)
  REF_COUNT=$(printf '%s\n' "$REFS" | grep -c . || true)
  if [ "${REF_COUNT:-0}" -lt 3 ]; then
    fail "$DSD references only ${REF_COUNT} path(s) under $CODE_DIR/ - it is not describing the delivered build."
  else
    GHOSTS=""
    for r in $REFS; do
      # Trim a trailing slash so a directory reference resolves.
      c="${r%/}"
      [ -e "$c" ] || GHOSTS="$GHOSTS $c"
    done
    if [ -n "$GHOSTS" ]; then
      fail "$DSD references path(s) that do not exist - it documents the design, not the delivery:$GHOSTS"
    else
      ok "all ${REF_COUNT} referenced $CODE_DIR/ paths exist"
    fi
  fi

  # --- the sections support actually opens --------------------------------
  COMP_SUBS=$(awk '
    /^## ([0-9]+\. )?Component Reference$/ { inside = 1; next }
    inside && /^## / { exit }
    inside && /^### / { n++ }
    END { print n + 0 }
  ' "$DSD")
  # Content lines only - the '###' headings are structure, not documentation, and
  # counting them would let four bare headings look like four documented components.
  COMP_LINES=$(awk '
    /^## ([0-9]+\. )?Component Reference$/ { inside = 1; next }
    inside && /^## / { exit }
    inside && /^### / { next }
    inside && NF { n++ }
    END { print n + 0 }
  ' "$DSD")
  # Depth is measured PER COMPONENT: four content lines is what it takes to give a
  # file path, a purpose, the inputs and outputs, and the error behaviour. A flat
  # total would only reward padding.
  COMP_MIN=$(( ${COMP_SUBS:-0} * 4 ))
  [ "$COMP_MIN" -ge 16 ] || COMP_MIN=16
  if [ "${COMP_SUBS:-0}" -lt 2 ]; then
    fail "$DSD Component Reference has only ${COMP_SUBS} '###' component(s) - document each one separately."
  elif [ "${COMP_LINES:-0}" -lt "$COMP_MIN" ]; then
    fail "$DSD Component Reference is ${COMP_LINES} lines for ${COMP_SUBS} components (needs ${COMP_MIN}) - under-documented."
  else
    ok "Component Reference: ${COMP_SUBS} components, ${COMP_LINES} lines (floor ${COMP_MIN})"
  fi

  rows_in() {
    awk -v want="$1" '
      $0 ~ "^## ([0-9]+\\. )?"want"$" { inside = 1; next }
      inside && /^## / { exit }
      inside && /^\|/ && $0 !~ /^\|[ :|-]+\|[ :|-]*$/ { n++ }
      END { print n + 0 }
    ' "$DSD"
  }

  for section in "Configuration Reference" "Business Rules Implemented" "Troubleshooting Guide"; do
    ROWS=$(rows_in "$section")
    if [ "${ROWS:-0}" -lt 3 ]; then
      fail "$DSD section '$section' has only ${ROWS} table row(s) - it must be a real table."
    else
      ok "'$section' has ${ROWS} table rows"
    fi
  done

  # Deviations may legitimately be empty, but it must say so rather than be blank.
  DEV_ROWS=$(rows_in "Deviations from Design")
  if [ "${DEV_ROWS:-0}" -lt 1 ]; then
    if grep -qiE 'no deviations|none - the build matches|no differences' "$DSD"; then
      ok "'Deviations from Design' states there are none"
    else
      fail "$DSD 'Deviations from Design' has no rows and does not state that there are none."
    fi
  else
    ok "'Deviations from Design' has ${DEV_ROWS} rows"
  fi

  # --- documentation, not a code dump -------------------------------------
  if grep -qE '<Activity|xmlns:ui=|xmlns:x="http://schemas.microsoft.com' "$DSD"; then
    fail "$DSD contains XAML - reference the file, do not paste it."
  else
    ok "no pasted implementation"
  fi

  # --- unfilled scaffolding ------------------------------------------------
  if LEFTOVERS=$(grep -nE '<[A-Z][A-Z0-9_]{2,}>|<placeholder|<one-line|<PATH_TO|<project name>|<product>|<skill>|<the measured-against|<YYYY-MM-DD>|<DATE>|<AUTHOR>' "$DSD"); then
    fail "$DSD has unfilled placeholders:"
    echo "$LEFTOVERS" | head -20
  else
    ok "no placeholders"
  fi

  if LEFTOVERS=$(grep -nEi '(\bTBD\b|Lorem ipsum|\bFIXME\b|XXXX)' "$DSD"); then
    fail "$DSD has placeholder text left in it:"
    echo "$LEFTOVERS" | head -20
  else
    ok "no placeholder text"
  fi

  EMPTY_TABLES=$(awk '
    /^\|[ :|-]+\|[ :|-]*$/ { sep = NR; next }
    sep && NR == sep + 1 && $0 !~ /^\|/ { print sep; sep = 0; next }
    sep && NR == sep + 1 { sep = 0 }
  ' "$DSD")
  if [ -n "$EMPTY_TABLES" ]; then
    fail "$DSD has empty table(s) at line(s): $(echo "$EMPTY_TABLES" | tr '\n' ' ')"
  else
    ok "all tables have data rows"
  fi

  # --- traceability against the SDD ---------------------------------------
  # A business rule the design required and the documentation never mentions means
  # nobody can tell whether it was built. That is the point of section 6.
  if [ -z "$SDD" ] || [ ! -f "$SDD" ]; then
    warn "source SDD '$SDD' not available - skipping traceability for $DSD"
  else
    MISSING_BR=""; COUNT_BR=0
    for id in $(grep -oE '\bBR-[0-9]+\b' "$SDD" | sort -u); do
      COUNT_BR=$((COUNT_BR + 1))
      grep -qF "$id" "$DSD" || MISSING_BR="$MISSING_BR $id"
    done
    if [ -n "$MISSING_BR" ]; then
      fail "business rules in $SDD are not accounted for in $DSD:$MISSING_BR"
    elif [ "$COUNT_BR" -gt 0 ]; then
      ok "all ${COUNT_BR} BR-xx rules from the SDD are accounted for"
    else
      warn "$SDD declares no BR-xx business rules - nothing to trace"
    fi

    IDS=$(grep -oE '\b[BS][0-9]+\b' "$SDD" | sort -u | tr '\n' ' ')
    if [ -n "${IDS// /}" ]; then
      PRESENT=0; MISSING_IDS=""
      for id in $IDS; do
        if grep -qE "\b$id\b" "$DSD"; then PRESENT=$((PRESENT + 1)); else MISSING_IDS="$MISSING_IDS $id"; fi
      done
      TOTAL=$(printf '%s' "$IDS" | wc -w | tr -d ' ')
      if [ "$PRESENT" -eq 0 ]; then
        fail "none of the ${TOTAL} exception/error IDs in $SDD appear in $DSD - section 7 is decorative."
      elif [ -n "$MISSING_IDS" ]; then
        warn "exception/error IDs not documented in $DSD (renamed, or not built?):$MISSING_IDS"
      else
        ok "all ${TOTAL} exception/error IDs are documented"
      fi
    fi
  fi
  echo
done <<< "$DECLARED"

if [ "$WARNINGS" -gt 0 ]; then
  echo "DSD validation raised ${WARNINGS} warning(s)."
fi
if [ "$FAILURES" -gt 0 ]; then
  echo "DSD validation FAILED with ${FAILURES} problem(s)."
  exit 1
fi
echo "DSD validation passed."
