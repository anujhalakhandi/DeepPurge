#!/usr/bin/env bash
# Builds the flashable module zip and update.json into dist/.
#   tools/build-module.sh   → dist/DeepPurge-v<version>.zip, dist/update.json
# The version comes from module/module.prop (version=v10.1, versionCode=1001).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${GITHUB_REPOSITORY:-anujhalakhandi/DeepPurge}

VER=$(sed -n 's/^version=v//p' module/module.prop)
CODE=$(sed -n 's/^versionCode=//p' module/module.prop)
[ -n "$VER" ] && [ -n "$CODE" ] || { echo "version= / versionCode= missing in module/module.prop" >&2; exit 1; }
MAJ=${VER%%.*}; MIN=${VER#*.}; MIN=${MIN%%.*}
[ "$CODE" = $((10#$MAJ * 100 + 10#$MIN)) ] || { echo "versionCode $CODE doesn't match version $VER (expected $((10#$MAJ * 100 + 10#$MIN)))" >&2; exit 1; }
ZIP="DeepPurge-v$VER.zip"

rm -rf dist; mkdir -p dist
for f in module/*.sh; do sh -n "$f"; done
(cd module && zip -qr -X "../dist/$ZIP" . -x '*.DS_Store')

cat > dist/update.json <<JSON
{
  "version": "v$VER",
  "versionCode": $CODE,
  "zipUrl": "https://github.com/$REPO/releases/download/v$VER/$ZIP",
  "changelog": "https://raw.githubusercontent.com/$REPO/main/CHANGELOG.md"
}
JSON
echo "Built dist/$ZIP (v$VER, versionCode $CODE)"
