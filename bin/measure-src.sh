#!/usr/bin/env bash
# Prints the fastest warm run time (in seconds) of the phpstan-src checkout
# given as the first argument, on the generated project.
# Exit code 125 means "this commit cannot be tested" (git bisect skips it).

set -uo pipefail
cd "$(dirname "$0")/.."

src="$1"
runs="${2:-3}"
sha="$(git -C "$src" rev-parse --short HEAD)"

if ! composer install --working-dir="$src" --no-interaction --no-progress --quiet; then
    echo "composer install failed for $sha" >&2
    exit 125
fi

export CACHE_NAME="src-$sha"
rm -rf "tmp/$CACHE_NAME"
json="$(mktemp)"
# The warmup run fills the result cache, the timed runs then restore it.
if ! hyperfine --style none --warmup 1 --runs "$runs" --export-json "$json" -N \
    "$src/bin/phpstan analyse -c phpstan.neon --no-progress" > /dev/null 2>&1; then
    echo "PHPStan failed for $sha" >&2
    rm -f "$json"
    exit 125
fi

jq -r '.results[0].min' "$json" | xargs printf '%.3f\n'
rm -f "$json"
