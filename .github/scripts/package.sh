#!/usr/bin/env bash
# Builds the WoWUp-compatible release files into ./dist:
#   CamelusBetterBlessings-<version>-forever.zip   (zip contains CamelusBetterBlessings/ folder)
#   release.json                                   (BigWigs-packager style metadata, flavor "forever")
# WoWUp's GitHub provider accepts either a zip ending in -forever.zip / -camelot.zip
# or a release.json entry with flavor "forever"; we publish both.
# Usage: .github/scripts/package.sh v1.2.3
set -euo pipefail

ADDON="CamelusBetterBlessings"
VERSION="${1:?usage: package.sh <version>}"
TOC="${ADDON}.toc"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "::error::Version '$VERSION' must look like v1.2.3 or v1.2.3-beta.1" >&2
  exit 1
fi

INTERFACE="$(sed -n 's/^## Interface:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$TOC" | head -n1)"
if [ -z "$INTERFACE" ]; then
  echo "::error::No '## Interface:' line found in $TOC" >&2
  exit 1
fi

ZIP="${ADDON}-${VERSION}-forever.zip"
rm -rf dist
mkdir -p "dist/${ADDON}"

# The .toc is the source of truth for which Lua files ship.
mapfile -t FILES < <(grep -v '^##' "$TOC" | sed 's/[[:space:]]*$//' | grep -v '^$')
for f in "$TOC" "${FILES[@]}" Bindings.xml README.md LICENSE; do
  if [ -f "$f" ]; then
    mkdir -p "dist/${ADDON}/$(dirname "$f")"
    cp "$f" "dist/${ADDON}/$f"
  elif [ "$f" != "LICENSE" ] && [ "$f" != "README.md" ]; then
    echo "::error::File '$f' listed in $TOC is missing" >&2
    exit 1
  fi
done

sed -i "s/@project-version@/${VERSION}/g" "dist/${ADDON}/${TOC}"

(cd dist && zip -qr9 "$ZIP" "$ADDON")

cat > dist/release.json <<JSON
{
  "releases": [
    {
      "name": "${ADDON}",
      "version": "${VERSION}",
      "filename": "${ZIP}",
      "nolib": false,
      "metadata": [
        { "flavor": "forever", "interface": ${INTERFACE} }
      ]
    }
  ]
}
JSON

echo "zip=dist/${ZIP}"
echo "interface=${INTERFACE}"
unzip -l "dist/${ZIP}"
