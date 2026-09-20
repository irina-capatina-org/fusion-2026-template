#!/usr/bin/env bash
#
# Writes observability.json on the `observability` branch, which exists only to
# hold that file: nothing triggers on it and no content PR can revert it.
# The app reads it with no auth and no rate limit:
#   https://raw.githubusercontent.com/<owner>/<repo>/observability/observability.json
#
#   observe.sh set      k=v ...              # top level: epicKey, repo
#   observe.sh stage    <Stage> k=v ...      # status=todo|in-progress|in-review|done|faulted
#   observe.sh document <kind>  k=v ...      # kind: pdd | sdd | dsd
#
# A stage carries decidedBy=human|agent|auto alongside status=in-review, which is
# what tells the app whether the gate is a person's or a bot's.
#
# updatedAt is stamped on whatever you touch; createdAt is set once, by `set`.
# Values that look numeric or boolean are written as such. Every write merges
# into its own key, so it can never erase a field it does not know about.
#
# Needs GH_TOKEN with contents:write. REPO defaults to $GITHUB_REPOSITORY.

set -euo pipefail

FILE=observability.json
BRANCH=observability
REPO="${REPO:-${GITHUB_REPOSITORY:?REPO or GITHUB_REPOSITORY required}}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

what="${1:?set|stage|document}"; shift
case "$what" in
  set)             key="" ;;
  stage|document)  key="${1:?name required}"; shift ;;
  *) echo "observe.sh: unknown target '$what'" >&2; exit 2 ;;
esac

# A typo'd status silently freezes a card, and there are ~20 call sites.
for kv in "$@"; do
  case "$kv" in
    status=*) case "${kv#status=}" in
                todo|in-progress|in-review|done|faulted) ;;
                *) echo "observe.sh: bad status '${kv#status=}'" >&2; exit 2 ;;
              esac ;;
    decidedBy=*) case "${kv#decidedBy=}" in
                   human|agent|auto) ;;
                   *) echo "observe.sh: bad decidedBy '${kv#decidedBy=}'" >&2; exit 2 ;;
                 esac ;;
  esac
done

# k=v pairs -> one JSON object
patch='{}'
for kv in "$@"; do
  k="${kv%%=*}"; v="${kv#*=}"
  if [[ "$v" =~ ^-?[0-9]+$ || "$v" == true || "$v" == false || "$v" == null ]]; then
    patch="$(jq -c --arg k "$k" --argjson v "$v" '. + {($k): $v}' <<<"$patch")"
  else
    patch="$(jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}' <<<"$patch")"
  fi
done

case "$what" in
  set)      prog='. + $p | .createdAt = (.createdAt // $now)' ;;
  stage)    prog='.stages[$k]    = ((.stages[$k]    // {}) + $p + {updatedAt: $now})' ;;
  document) prog='.documents[$k] = ((.documents[$k] // {}) + $p + {updatedAt: $now})' ;;
esac

# Read-modify-write through the contents API — no clone, no working tree. The
# sha is the optimistic lock: if a concurrent write landed first the PUT is
# rejected and we reapply the same merge on top of the new file.
for attempt in 1 2 3 4 5; do
  got="$(gh api "repos/$REPO/contents/$FILE?ref=$BRANCH")"
  sha="$(jq -r .sha <<<"$got")"
  cur="$(jq -r .content <<<"$got" | base64 -d)"

  new="$(jq --arg k "$key" --arg now "$NOW" --argjson p "$patch" "$prog" <<<"$cur")"

  if [ "$(jq -S . <<<"$cur")" = "$(jq -S . <<<"$new")" ]; then
    echo "observe.sh: no change ($what ${key:-root})"
    exit 0
  fi

  if gh api -X PUT "repos/$REPO/contents/$FILE" \
       -f branch="$BRANCH" -f sha="$sha" \
       -f message="observe: $what ${key:-root}" \
       -f content="$(base64 <<<"$new" | tr -d '\n')" >/dev/null 2>&1; then
    echo "observe.sh: $what ${key:-root} ${*:-}"
    exit 0
  fi

  echo "observe.sh: write conflict, retrying ($attempt/5)" >&2
  sleep $((attempt * 2))
done

echo "observe.sh: could not write $FILE after 5 attempts" >&2
exit 1
