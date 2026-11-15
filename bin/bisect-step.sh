#!/usr/bin/env bash
# Used by "git bisect run" in bin/bisect.sh. Marks a commit as bad when the
# warm run is slower than THRESHOLD seconds.

set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$(pwd)"

time="$("$root/bin/measure-src.sh" "$src")" || exit 125
subject="$(git log -1 --format='%h %s')"

if awk -v t="$time" -v max="$THRESHOLD" 'BEGIN { exit !(t > max) }'; then
    verdict=bad
else
    verdict=good
fi

printf '%s\t%s\t%s\n' "$time" "$verdict" "$subject" | tee -a "$root/results/bisect-steps.tsv"
[ "$verdict" = good ]
