#!/usr/bin/env bash
# Copies the seal, the flags and the mark out of the Android repository, which is where they are
# versioned.
#
# The 26 canton flags are the public-domain Commons SVGs the Android app ships as assets; here
# each becomes an image set that keeps its vector form, which is the one way iOS renders an SVG
# at any size without a library. The seal (limen_logo_master.xml, a VectorDrawable) is rewritten
# as an SVG by tools/marks.py, since VectorDrawable path data is SVG path data. The 512 px mark
# goes into the kit for the PDF's badge, the same raster Android prints.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID="${LIMEN_ANDROID:-$HERE/../../ANDROID/limen}"
ASSETS="$ANDROID/app/src/main/assets"
RES="$ANDROID/app/src/main/res"
CATALOG="$HERE/Limen/Resources/Assets.xcassets"

if [[ ! -d "$ASSETS" ]]; then
    echo "Android assets not found at $ASSETS (set LIMEN_ANDROID)" >&2
    exit 66
fi

echo "==> flags into the asset catalog"
for svg in "$ASSETS"/cantons/*.svg; do
    code="$(basename "$svg" .svg)"
    set="$CATALOG/flag-$code.imageset"
    mkdir -p "$set"
    cp "$svg" "$set/$code.svg"
    cat > "$set/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$code.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "original"
  }
}
JSON
done
cp "$ASSETS/cantons/manifest.json" "$HERE/LimenKit/Resources/cantons-manifest.json"

echo "==> the seal"
python3 "$HERE/tools/marks.py" "$RES/drawable/limen_logo_master.xml" "$CATALOG/limen-seal.imageset/limen-seal.svg"
cat > "$CATALOG/limen-seal.imageset/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "limen-seal.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "original"
  }
}
JSON

echo "==> the mark for the PDF badge"
cp "$RES/drawable-nodpi/limen_mark.png" "$HERE/LimenKit/Resources/limen_mark.png"
