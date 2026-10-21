#!/usr/bin/env bash
# Builds libjxl from the pinned source tools/fetch-deps.sh placed in ThirdParty/libjxl into one
# static XCFramework for the iPhone and the simulator, which Project.swift links into LimenJxl.
# Only what the backup repacking needs, as the Android app's CMakeLists.txt builds it: a static
# build, no tools, tests, plugins or JNI; JPEG transcoding, boxes and skcms on; one Highway SIMD
# target, because every arm64 iPhone and every Apple silicon simulator runs NEON. Size over speed
# (MinSizeRel), as the Android build chose.
#
# Run from the repo root:  bash tools/build-libjxl.sh
# The output, ThirdParty/LimenJxl.xcframework, is gitignored with the source.

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="ThirdParty/libjxl"
OUT="ThirdParty/LimenJxl.xcframework"
BUILD="ThirdParty/build"
HWY_TARGET="${LIMEN_HWY_TARGET:-NEON}"

if [ ! -f "$SRC/lib/include/jxl/encode.h" ]; then
  echo "libjxl source is missing. Run: bash tools/fetch-deps.sh" >&2
  exit 1
fi

OFF=(JPEGXL_ENABLE_TOOLS JPEGXL_ENABLE_DEVTOOLS JPEGXL_ENABLE_DOXYGEN JPEGXL_ENABLE_MANPAGES
     JPEGXL_ENABLE_BENCHMARK JPEGXL_ENABLE_EXAMPLES JPEGXL_ENABLE_JNI JPEGXL_ENABLE_SJPEG
     JPEGXL_ENABLE_OPENEXR JPEGXL_ENABLE_PLUGINS JPEGXL_ENABLE_VIEWERS JPEGXL_BUNDLE_LIBPNG
     JPEGXL_ENABLE_FUZZERS JPEGXL_ENABLE_COVERAGE JPEGXL_STATIC JPEGXL_ENABLE_TCMALLOC)
ON=(JPEGXL_ENABLE_SKCMS JPEGXL_ENABLE_TRANSCODE_JPEG JPEGXL_ENABLE_BOXES)
HWY=(AVX2 AVX3 AVX3_DL AVX3_SPR AVX3_ZEN4 EMU128 NEON NEON_BF16 NEON_WITHOUT_AES PPC10 PPC8
     PPC9 RVV SCALAR SSE2 SSE4 SSSE3 SVE SVE_256 SVE2 SVE2_128 WASM WASM_EMU256 Z14 Z15)

build() {
  # build <slice> <sysroot>
  local slice="$1" sysroot="$2" dir="$BUILD/$1"
  local args=(-S "$SRC" -B "$dir" -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=MinSizeRel
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCMAKE_CXX_STANDARD=17)
  for o in "${OFF[@]}"; do args+=("-D$o=OFF"); done
  for o in "${ON[@]}"; do args+=("-D$o=ON"); done
  for t in "${HWY[@]}"; do args+=("-DJPEGXL_ENABLE_HWY_$t=OFF"); done
  args+=("-DJPEGXL_ENABLE_HWY_$HWY_TARGET=ON")
  cmake "${args[@]}"
  cmake --build "$dir" --target jxl jxl_cms
  # Everything the two targets pulled in, in one archive: the linker needs the pieces together.
  local libs
  libs=$(find "$dir/lib" "$dir/third_party" -name '*.a' | sort)
  echo "$slice archives:"; echo "$libs" | sed 's/^/  /'
  libtool -static -o "$dir/libLimenJxl.a" $libs
  mkdir -p "$dir/include/jxl"
  cp "$SRC"/lib/include/jxl/*.h "$dir/include/jxl/"
  cp "$dir"/lib/include/jxl/*.h "$dir/include/jxl/"
}

rm -rf "$OUT" "$BUILD/iphoneos" "$BUILD/iphonesimulator"
build iphoneos iphoneos
build iphonesimulator iphonesimulator
xcodebuild -create-xcframework \
  -library "$BUILD/iphoneos/libLimenJxl.a" -headers "$BUILD/iphoneos/include" \
  -library "$BUILD/iphonesimulator/libLimenJxl.a" -headers "$BUILD/iphonesimulator/include" \
  -output "$OUT"
du -sh "$OUT" "$BUILD/iphoneos/libLimenJxl.a" "$BUILD/iphonesimulator/libLimenJxl.a"
echo "built $OUT with Highway target $HWY_TARGET"
