#!/usr/bin/env bash
# Fetches the source that is deliberately not in git: libjxl and the three libraries it builds
# from, for the JPEG XL repacking of photographs in a backup. The same archives and sha256 digests
# as the Android app's tools/fetch-deps.sh, so both apps repack with the same libjxl.
#
# Why not vendor it? Git keeps every version forever, and the sources weigh more than the app.
# Why tarballs and not submodules? One script with digests keeps the rule simple: everything not
# in git arrives through this file, pinned, and a changed upstream archive is a build error.
#
# Run from the repo root:  bash tools/fetch-deps.sh
# Then build the XCFramework: bash tools/build-libjxl.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# libjxl 0.12.0, and the brotli, highway and skcms commits its own deps.sh pins for that tag.
LIBJXL_TAG="v0.12.0"
LIBJXL_URL="https://github.com/libjxl/libjxl/archive/refs/tags/${LIBJXL_TAG}.tar.gz"
LIBJXL_SHA256="03e9be69a30be4011f559da75328b6d7cea8ad921fabfbd551ce10bf45cdc992"
BROTLI_URL="https://github.com/google/brotli/archive/028fb5a23661f123017c060daa546b55cf4bde29.tar.gz"
BROTLI_SHA256="0afe09a53c8bad9861c8dd1fc1284308d54f19d2979ba3541cfdcc9b05fe360f"
HIGHWAY_URL="https://github.com/google/highway/archive/457c891775a7397bdb0376bb1031e6e027af1c48.tar.gz"
HIGHWAY_SHA256="5124b0501c98d9930dbb065bfa1a5bbbd59ce0f12facb7e1e33aaef01a5f1f1a"
SKCMS_URL="https://github.com/google/skcms/archive/96d9171c94b937a1b5f0293de7309ac16311b722.tar.gz"
SKCMS_SHA256="9bb4b5bba0b7c04f6c2bce9ff713d61e23c9a20c4945161ae16290498ad74627"

LIBJXL_DIR="ThirdParty/libjxl"
WORK="ThirdParty/.download"

verify() {
  # verify <file> <sha256>: macOS ships shasum, not sha256sum.
  [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ]
}

fetch() {
  # fetch <url> <sha256> <dest>
  curl -L --fail --progress-bar -o "$3" "$1"
  if ! verify "$3" "$2"; then
    rm -f "$3"
    echo "ERROR: $1 does not match the pinned sha256 $2" >&2
    echo "Either the download was corrupted or upstream changed the archive; do not build with it." >&2
    exit 1
  fi
}

if [ -f "$LIBJXL_DIR/.fetched-$LIBJXL_TAG" ]; then
  echo "libjxl $LIBJXL_TAG already present: $LIBJXL_DIR"
  exit 0
fi

rm -rf "$WORK" "$LIBJXL_DIR"
mkdir -p "$WORK"
echo "downloading libjxl $LIBJXL_TAG and its dependencies ..."
fetch "$LIBJXL_URL" "$LIBJXL_SHA256" "$WORK/libjxl.tar.gz"
fetch "$BROTLI_URL" "$BROTLI_SHA256" "$WORK/brotli.tar.gz"
fetch "$HIGHWAY_URL" "$HIGHWAY_SHA256" "$WORK/highway.tar.gz"
fetch "$SKCMS_URL" "$SKCMS_SHA256" "$WORK/skcms.tar.gz"

# The benchmark metrics are symbolic links nothing here builds.
tar -xzf "$WORK/libjxl.tar.gz" -C "$WORK" --exclude='libjxl-0.12.0/tools/benchmark/metrics'
mv "$WORK/libjxl-0.12.0" "$LIBJXL_DIR"
for dep in brotli highway skcms; do
  rm -rf "$LIBJXL_DIR/third_party/$dep"
  mkdir -p "$LIBJXL_DIR/third_party/$dep"
  tar -xzf "$WORK/$dep.tar.gz" -C "$LIBJXL_DIR/third_party/$dep" --strip-components=1
done
rm -rf "$WORK"
touch "$LIBJXL_DIR/.fetched-$LIBJXL_TAG"
echo "unpacked libjxl $LIBJXL_TAG into $LIBJXL_DIR"
