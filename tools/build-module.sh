#!/usr/bin/env bash
# Builds the flashable module zip and update.json into dist/.
#   tools/build-module.sh            → dist/DeepPurge-v<VERSION>.zip, dist/update.json
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${GITHUB_REPOSITORY:-anujhalakhandi/DeepPurge}

VER=$(sed -n 's/^VERSION="\(.*\)"/\1/p' deeppurge.sh | head -n 1)
[ -n "$VER" ] || { echo "VERSION= not found in deeppurge.sh" >&2; exit 1; }
MAJ=${VER%%.*}; MIN=${VER#*.}; MIN=${MIN%%.*}
CODE=$((10#$MAJ * 100 + 10#$MIN))          # 10.1 → 1001
ZIP="DeepPurge-v$VER.zip"

rm -rf dist; mkdir -p dist/module
cp -r module/. dist/module/
sed -i "s/@VERSION@/$VER/; s/@VERSIONCODE@/$CODE/" dist/module/module.prop
cp deeppurge.sh dist/module/deeppurge.sh

# tuning.sh — the same file the engine writes when the module is installed (install_tuning)
{
  echo '#!/system/bin/sh'
  echo '# DEEPPURGE tuning — run by the module: post-fs-data.sh (PASS=1), service.sh (PASS=2)'
  echo 'PASS=${PASS:-now}'
  awk "/cat << 'TUNE_EOF'/{f=1;next} /^TUNE_EOF/{f=0} f" deeppurge.sh
} > dist/module/tuning.sh
grep -q '^w /' dist/module/tuning.sh || { echo "tuning_body not found in deeppurge.sh" >&2; exit 1; }
sh -n dist/module/tuning.sh

find dist/module -name '*.sh' -exec chmod 755 {} +
chmod 755 dist/module/META-INF/com/google/android/update-binary
(cd dist/module && zip -qr -X "../$ZIP" .)

cat > dist/update.json <<JSON
{
  "version": "v$VER",
  "versionCode": $CODE,
  "zipUrl": "https://github.com/$REPO/releases/download/v$VER/$ZIP",
  "changelog": "https://raw.githubusercontent.com/$REPO/main/CHANGELOG.md"
}
JSON
echo "Built dist/$ZIP (v$VER, versionCode $CODE)"
