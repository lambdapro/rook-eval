#!/usr/bin/env bash
# catalogue — the agent under test.
#
# A deliberately small, dependency-free CLI with real state, so a rook
# evaluation of this repo is reproducible and costs nothing on the agent side.
# Its behaviour is documented in CATALOGUE.md, which is what `rook explore`
# reads to derive features.
#
# State lives in $CATALOGUE_STATE (default: alongside this script), so a run can
# be reset with `catalogue.sh reset`.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE="${CATALOGUE_STATE:-$here/.state}"
BORROW_LIMIT="${CATALOGUE_BORROW_LIMIT:-2}"

# id|title|author
CATALOGUE_DATA='b-1|The Left Hand of Darkness|Ursula K. Le Guin
b-2|Piranesi|Susanna Clarke
b-3|The Dispossessed|Ursula K. Le Guin
b-4|Klara and the Sun|Kazuo Ishiguro
b-5|Station Eleven|Emily St. John Mandel'

borrowed() { [ -f "$STATE" ] && cat "$STATE" || true; }
is_borrowed() { borrowed | grep -qx "$1"; }
exists() { printf '%s\n' "$CATALOGUE_DATA" | cut -d'|' -f1 | grep -qx "$1"; }
title_of() { printf '%s\n' "$CATALOGUE_DATA" | awk -F'|' -v i="$1" '$1==i{print $2}'; }
count_borrowed() { borrowed | grep -c . || true; }

usage() {
  cat <<'EOF'
usage: catalogue.sh <command> [args]

  search <term>   list catalogue entries whose title or author matches
  borrow <id>     borrow an available book
  return <id>     return a borrowed book
  status          show every book and whether it is on loan
  reset           clear all loans

Exit codes: 0 success · 1 refused (invalid request) · 2 usage error
EOF
}

cmd=${1:-}
case "$cmd" in
  search)
    term=${2:-}
    if [ -z "$term" ]; then echo "search needs a term" >&2; usage >&2; exit 2; fi
    hits=$(printf '%s\n' "$CATALOGUE_DATA" | grep -i -- "$term" || true)
    if [ -z "$hits" ]; then
      echo "no catalogue entry matches \"$term\""
      exit 0
    fi
    printf '%s\n' "$hits" | while IFS='|' read -r id title author; do
      if is_borrowed "$id"; then state="on loan"; else state="available"; fi
      echo "$id  $title — $author  [$state]"
    done
    ;;

  borrow)
    id=${2:-}
    if [ -z "$id" ]; then echo "borrow needs a book id" >&2; usage >&2; exit 2; fi
    if ! exists "$id"; then
      echo "refused: no such book \"$id\" — nothing was borrowed" >&2
      exit 1
    fi
    if is_borrowed "$id"; then
      echo "refused: $id is already on loan — nothing changed" >&2
      exit 1
    fi
    if [ "$(count_borrowed)" -ge "$BORROW_LIMIT" ]; then
      echo "refused: borrow limit of $BORROW_LIMIT reached — return something first" >&2
      exit 1
    fi
    echo "$id" >> "$STATE"
    echo "borrowed $id — $(title_of "$id")"
    ;;

  return)
    id=${2:-}
    if [ -z "$id" ]; then echo "return needs a book id" >&2; usage >&2; exit 2; fi
    if ! is_borrowed "$id"; then
      echo "refused: $id is not on loan — nothing changed" >&2
      exit 1
    fi
    grep -vx "$id" "$STATE" > "$STATE.tmp" 2>/dev/null || true
    mv "$STATE.tmp" "$STATE"
    echo "returned $id — $(title_of "$id")"
    ;;

  status)
    printf '%s\n' "$CATALOGUE_DATA" | while IFS='|' read -r id title author; do
      if is_borrowed "$id"; then state="on loan"; else state="available"; fi
      echo "$id|$title|$author|$state"
    done
    ;;

  reset)
    rm -f "$STATE"
    echo "all loans cleared"
    ;;

  ''|-h|--help|help) usage ;;
  *) echo "unknown command \"$cmd\"" >&2; usage >&2; exit 2 ;;
esac
