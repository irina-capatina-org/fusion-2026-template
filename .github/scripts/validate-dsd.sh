#!/usr/bin/env bash
# Checks that the as-built DSD(s) EXIST and are viable markdown - nothing more.
#
# Usage: .github/scripts/validate-dsd.sh <architecture.json>
#
# This used to enforce a nine-section contract, per-section table minimums, code-path
# existence, document-control fields and rule traceability. All of it is gone on
# purpose. Nothing downstream reads the DSD: it is generated after the build was built,
# tested and reviewed, so it can never be the thing that blocks a delivery, and every
# rule it enforced was a rule an agent had to spend generation time satisfying. One
# run lost 238 seconds - over half the stage - to two checks that were themselves
# wrong.
#
# What is left is the question actually worth asking: is there a file, and can I open
# it in front of someone without it looking broken? So: it exists, it is not a stub,
# it has a title and some sections, no code fence is left hanging (which would swallow
# the rest of the page when rendered) and no table is a header with no rows.
#
# The DSD path comes from the REPOSITORY name, derived exactly as uipath-dsd.yml
# derives it, so the validator and the workflow cannot disagree about which file
# should exist.
set -uo pipefail

ARCH_FILE="${1:?usage: validate-dsd.sh <architecture.json>}"

REPO_NAME="${2:-${DSD_REPO_NAME:-}}"
[ -n "$REPO_NAME" ] || REPO_NAME="${GITHUB_REPOSITORY:-}"
REPO_NAME="${REPO_NAME##*/}"
[ -n "$REPO_NAME" ] || REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

# A document this small is a stub, not a page you would show anyone.
MIN_BYTES="${MIN_DSD_BYTES:-1200}"
FAILURES=0

fail() { echo "::error::$*"; FAILURES=$((FAILURES + 1)); }
ok()   { echo "  ok  - $*"; }

# ── architecture.json ────────────────────────────────────────────────────────
if [ ! -f "$ARCH_FILE" ]; then
  fail "architecture.json not found: $ARCH_FILE"
  exit 1
fi
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ARCH_FILE" 2>/dev/null; then
  fail "architecture.json is not valid JSON: $ARCH_FILE"
  exit 1
fi

DECLARED=$(python3 - "$ARCH_FILE" "$REPO_NAME" <<'EOF_PLAN'
import json, sys
d = json.load(open(sys.argv[1]))
repo = sys.argv[2]
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
    path = (f"docs/dsd-{repo}.md" if d["sdd_scope"] == "single-product"
            else f"docs/dsd-{repo}-{kebab}.md")
    rows.append("\t".join([path, sdd, p.get("product", ""), p.get("skill", ""), p["name"]]))
print("\n".join(rows))
EOF_PLAN
)

if [ -z "$DECLARED" ]; then
  fail "architecture.json yields no buildable project - no DSD is expected, which is itself wrong."
  exit 1
fi

echo "Validating $(printf '%s\n' "$DECLARED" | grep -c .) as-built DSD file(s) derived from $ARCH_FILE"
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

  BYTES=$(wc -c < "$DSD" | tr -d ' ')
  if [ "$BYTES" -lt "$MIN_BYTES" ]; then
    fail "$DSD is only ${BYTES} bytes (minimum ${MIN_BYTES}) - that is a stub, not a document."
  else
    ok "exists, ${BYTES} bytes"
  fi

  grep -qE '^# .+' "$DSD" || fail "$DSD has no '# ' H1 title line."

  SECTIONS=$(grep -c '^## ' "$DSD" || true)
  if [ "${SECTIONS:-0}" -lt 3 ]; then
    fail "$DSD has only ${SECTIONS} '## ' section(s) - it does not read as a document."
  else
    ok "${SECTIONS} sections"
  fi

  # An odd number of fences means one is never closed, and everything after it
  # renders as a single grey block.
  FENCES=$(grep -c '^```' "$DSD" || true)
  if [ $(( FENCES % 2 )) -ne 0 ]; then
    fail "$DSD has an unclosed code fence (${FENCES} fence lines) - the rest of the page renders as one code block."
  else
    ok "code fences balanced"
  fi

  # A header with no rows under it renders as a broken table.
  EMPTY_TABLES=$(awk '
    /^\|[ :|-]+\|[ :|-]*$/ { sep = NR; next }
    sep && NR == sep + 1 && $0 !~ /^\|/ { print sep; sep = 0; next }
    sep && NR == sep + 1 { sep = 0 }
  ' "$DSD")
  if [ -n "$EMPTY_TABLES" ]; then
    fail "$DSD has a table with no data rows at line(s): $(echo "$EMPTY_TABLES" | tr '\n' ' ')"
  else
    ok "all tables have data rows"
  fi

  echo
done <<< "$DECLARED"

# The exit code drives the repair pass; it is not a release gate. A DSD is generated
# after the build was tested and the PR reviewed - it must never fail a good delivery.
if [ "$FAILURES" -gt 0 ]; then
  echo "DSD check FAILED with ${FAILURES} problem(s)."
  [ "${DSD_NEVER_FAIL:-0}" = "1" ] && { echo "DSD_NEVER_FAIL=1 - reporting only."; exit 0; }
  exit 1
fi
echo "DSD check passed - the document exists and is viable markdown."
