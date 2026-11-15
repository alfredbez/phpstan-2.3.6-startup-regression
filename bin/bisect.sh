#!/usr/bin/env bash
# Finds the phpstan-src commit that makes the warm run slow.
#
# Usage: bin/bisect.sh [good tag] [bad tag]
#
# Needs: php, composer, git, hyperfine, jq. Run "php generate.php" and
# "composer install" first.

set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

good="${1:-2.3.5}"
bad="${2:-2.3.6}"
src="$root/phpstan-src"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ ! -d "$src" ]; then
    git clone --quiet --filter=blob:none https://github.com/phpstan/phpstan-src.git "$src"
fi

mkdir -p results
: > results/bisect-steps.tsv

git -C "$src" checkout --quiet "$good"
time_good="$(bin/measure-src.sh "$src" 5)"
git -C "$src" checkout --quiet "$bad"
time_bad="$(bin/measure-src.sh "$src" 5)"
threshold="$(awk -v a="$time_good" -v b="$time_bad" 'BEGIN { printf "%.3f", (a + b) / 2 }')"

echo "phpstan-src $good: ${time_good}s, $bad: ${time_bad}s (fastest of 5 warm runs)"
echo "A commit is bad when its fastest warm run takes more than ${threshold}s"
echo

export THRESHOLD="$threshold"
git -C "$src" bisect start "$bad" "$good" > /dev/null
(cd "$src" && git bisect run "$root/bin/bisect-step.sh")
first_bad="$(git -C "$src" rev-parse refs/bisect/bad)"
git -C "$src" bisect log > results/bisect.log
git -C "$src" bisect reset > /dev/null 2>&1

parent_time="$(git -C "$src" checkout --quiet "$first_bad^" && bin/measure-src.sh "$src" 5)"
bad_time="$(git -C "$src" checkout --quiet "$first_bad" && bin/measure-src.sh "$src" 5)"

echo
echo "First bad commit: https://github.com/phpstan/phpstan-src/commit/$first_bad"
git -C "$src" log -1 --format='%h %s (%ad)' --date=short "$first_bad"
echo "Its parent: ${parent_time}s, the commit: ${bad_time}s (fastest of 5 warm runs)"

{
    echo "## git bisect in phpstan-src between $good and $bad"
    echo
    echo "Fastest of 5 warm runs, from source: $good **${time_good}s**, $bad **${time_bad}s**. Threshold for \"bad\": ${threshold}s."
    echo
    echo "| Warm run (s) | Verdict | Commit |"
    echo "| ---: | --- | --- |"
    while IFS=$'\t' read -r t v s; do
        echo "| $t | $v | $s |"
    done < results/bisect-steps.tsv
    echo
    echo "**First bad commit:** [$(git -C "$src" log -1 --format='%h %s' "$first_bad")](https://github.com/phpstan/phpstan-src/commit/$first_bad)"
    echo
    echo "Check of this commit against its parent (fastest of 5 warm runs): parent **${parent_time}s**, commit **${bad_time}s**."
} >> "$summary"
