#!/usr/bin/env bash
# Build the deck and publish it to GitHub Pages (gh-pages branch of Isaaciwd/Group-Meeting-Talk-2026-11).
# Live at https://isaaciwd.github.io/Group-Meeting-Talk-2026-11/
set -euo pipefail
cd "$(dirname "$0")"
REPO=git@github.com:Isaaciwd/Group-Meeting-Talk-2026-11.git
rm -rf dist
npx slidev build slides.md --base /Group-Meeting-Talk-2026-11/
touch dist/.nojekyll            # serve files as-is (no Jekyll processing)
cd dist
git init -q -b gh-pages
git add -A
git commit -q -m "Deploy $(date -u +%Y-%m-%dT%H:%MZ)"
git push -f "$REPO" gh-pages
rm -rf .git
echo "Published: https://isaaciwd.github.io/Group-Meeting-Talk-2026-11/"
