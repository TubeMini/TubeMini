#!/usr/bin/env bash
# Publishes the website (site/) and the Cydia repository to GitHub Pages (TubeMini/TubeMini.github.io).
#
#   scripts/publish-site.sh [package.deb ...] [--notes "Có gì mới"]
#
# New .deb files are added to cydia/debs (older ones stay), then Packages / Release / update.json are
# rebuilt (scripts/make-cydia-repo.py). Needs `gh` logged in with push access to the organisation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGES_REPO="TubeMini/TubeMini.github.io"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> clone $PAGES_REPO"
gh repo clone "$PAGES_REPO" "$WORK" -- -q
# Same author as the main repository (its GitHub no-reply address), never a guessed user@machine
git -C "$WORK" config user.name "$(git -C "$ROOT" config user.name)"
git -C "$WORK" config user.email "$(git -C "$ROOT" config user.email)"
echo "==> site/ → pages"
# Everything but the Cydia packages and update.json comes from site/ (removed pages files disappear too)
find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git ! -name cydia ! -name update.json -exec rm -rf {} +
find "$WORK/cydia" -mindepth 1 -maxdepth 1 ! -name debs -exec rm -rf {} + 2>/dev/null || true
cp -R "$ROOT/site/." "$WORK/"
touch "$WORK/.nojekyll" # serve files as they are (no Jekyll)
echo "==> Cydia repository"
python "$ROOT/scripts/make-cydia-repo.py" "$WORK" "$@"
cd "$WORK"
git add -A
if git diff --cached --quiet; then
    echo "==> nothing changed"
    exit 0
fi
git commit -q -m "Publish site and Cydia repository ($(date -u +%Y-%m-%d))"
git push -q origin HEAD
echo "==> https://tubemini.github.io/ (GitHub Pages updates in a minute or two)"
