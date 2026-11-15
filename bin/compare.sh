#!/usr/bin/env bash
# Compares the run time of released PHPStan versions on the generated project.
#
# Usage: bin/compare.sh [runs] [version...]
# Example: bin/compare.sh 10 2.3.5 2.3.6
#
# Needs: php, curl, hyperfine. Run "php generate.php" and "composer install" first.

set -euo pipefail
cd "$(dirname "$0")/.."

runs="${1:-10}"
shift || true
versions=("$@")
if [ ${#versions[@]} -eq 0 ]; then
    versions=(2.3.5 2.3.6)
fi

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
lib_files="$(find src/Lib -name '*.php' | wc -l | tr -d ' ')"
small_files="$(find src/Small -name '*.php' | wc -l | tr -d ' ')"

mkdir -p tools results
for v in "${versions[@]}"; do
    if [ ! -f "tools/phpstan-$v.phar" ]; then
        curl -fsSL -o "tools/phpstan-$v.phar" "https://github.com/phpstan/phpstan/releases/download/$v/phpstan.phar"
    fi
done

echo "PHP files in src/Lib (autoloaded, not analysed): $lib_files"
echo "PHP files in src/Small (analysed): $small_files"
echo

echo "== One verbose run per version with a warm result cache"
for v in "${versions[@]}"; do
    export CACHE_NAME="warm-$v"
    php "tools/phpstan-$v.phar" analyse -c phpstan.neon --no-progress > /dev/null
    echo "-- PHPStan $v"
    php "tools/phpstan-$v.phar" analyse -c phpstan.neon --no-progress -vv 2>&1 \
        | grep -E 'Result cache|Elapsed time|Peak memory' | tee "results/verbose-$v.txt"
done
echo

warm=()
cold=()
for v in "${versions[@]}"; do
    warm+=(--command-name "$v warm" "CACHE_NAME=warm-$v php tools/phpstan-$v.phar analyse -c phpstan.neon --no-progress")
    cold+=(--prepare "rm -rf tmp/cold-$v" --command-name "$v cold" "CACHE_NAME=cold-$v php tools/phpstan-$v.phar analyse -c phpstan.neon --no-progress")
done

echo "== Warm: result cache from the previous run, nothing changed"
hyperfine --warmup 1 --runs "$runs" --export-markdown results/warm.md --export-json results/warm.json "${warm[@]}"
echo

echo "== Cold: tmpDir deleted before each run"
hyperfine --runs "$runs" --export-markdown results/cold.md --export-json results/cold.json "${cold[@]}"

{
    echo "## PHPStan ${versions[*]}"
    echo
    echo "Only src/Small ($small_files files) is analysed. src/Lib has $lib_files files that are only in the Composer autoload section."
    echo
    echo "### Warm (result cache from the previous run, nothing changed)"
    echo
    cat results/warm.md
    echo
    echo "### Cold (tmpDir deleted before each run)"
    echo
    cat results/cold.md
    echo
    echo "### PHPStan's own output with -vv (warm)"
    echo
    for v in "${versions[@]}"; do
        echo "**$v**"
        echo
        echo '```'
        cat "results/verbose-$v.txt"
        echo '```'
        echo
    done
} >> "$summary"
