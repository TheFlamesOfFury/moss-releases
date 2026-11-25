#!/usr/bin/env bash
# Builds Moss for Windows's ffmpeg helper from source, LGPL-only, with only what Moss uses:
# LAME (MP3), Opus (OGG), libwebp (WebP), libaom (AVIF) and zlib (PNG), plus ffmpeg's own
# decoders and Windows' Media Foundation encoders. Like scripts/build-ffmpeg.sh on the Mac
# (owner's choice, 2026-11-25: from source rather than a ready-made build; docs/THIRD_PARTY.md).
#
# Run in MSYS2's MINGW64 shell (winget install MSYS2.MSYS2; then the tools below):
#   pacman -S --needed make diffutils tar xz perl mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm \
#     mingw-w64-x86_64-cmake mingw-w64-x86_64-pkgconf mingw-w64-x86_64-ninja
#   Apps/Windows/build-ffmpeg.sh
# Output: Apps/Windows/build/ffmpeg/ (ffmpeg.exe, licences, BUILD-INFO.txt); not committed.
#
# Sources come only from each project's official release address over HTTPS, and a build
# refuses any file whose SHA-256 differs from the one pinned here. ffmpeg, LAME and libwebp
# use the Mac's pins (scripts/ffmpeg-hashes.env). Opus is pinned from Xiph's SHA256SUMS;
# libaom (signed with GPG, no checksum file) and zlib from the official archives, checked
# against MSYS2's own package pins (2026-11-25). Change a version → update its hash too.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO/scripts/ffmpeg-hashes.env"

FFMPEG_VERSION=7.1.1
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
LAME_VERSION=3.100
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
WEBP_VERSION=1.5.0
WEBP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz"
OPUS_VERSION=1.6.1
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
AOM_VERSION=3.15.3
AOM_URL="https://storage.googleapis.com/aom-releases/libaom-$AOM_VERSION.tar.gz"
AOM_SHA256=12c01dc731ed7b5a999e28120b45bf58a002ba3435a4ba2cfbc1e084a27c9c04
ZLIB_VERSION=1.4
ZLIB_URL="https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.xz"
ZLIB_SHA256=4f11c512053d7bab8d9e9b89bde3575add3e4c50a383b42ef6cb837035fc5a7c

DOWNLOADS="$HERE/build/downloads"
OUT="$HERE/build/ffmpeg"
# Built in a neutral folder: ffmpeg records its build paths inside the program, and they must
# not carry the Windows username.
WORK=/tmp/moss-ffmpeg-build
PREFIX="$WORK/prefix"
JOBS="$(nproc)"

fetch() { # name url sha256
    local name=$1 url=$2 sha=$3 file
    mkdir -p "$DOWNLOADS"
    file="$DOWNLOADS/$(basename "$url")"
    [ -f "$file" ] || curl --fail --location --proto '=https' --tlsv1.2 -o "$file.part" "$url"
    [ -f "$file.part" ] && mv "$file.part" "$file"
    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$sha" ]; then
        rm -f "$file"
        echo "$name: SHA-256 is $actual, not the pinned $sha. Removed it: FAILED" >&2
        exit 1
    fi
}

unpack() { # name dir
    rm -rf "$2"
    mkdir -p "$2"
    tar -xf "$DOWNLOADS/$(basename "$3")" -C "$2" --strip-components=1
}

fetch ffmpeg "$FFMPEG_URL" "$FFMPEG_SHA256"
fetch lame "$LAME_URL" "$LAME_SHA256"
fetch libwebp "$WEBP_URL" "$WEBP_SHA256"
fetch opus "$OPUS_URL" "$OPUS_SHA256"
fetch libaom "$AOM_URL" "$AOM_SHA256"
fetch zlib "$ZLIB_URL" "$ZLIB_SHA256"

rm -rf "$WORK"
mkdir -p "$PREFIX"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export CFLAGS="-O2"

echo "== zlib $ZLIB_VERSION =="
unpack zlib "$WORK/zlib" "$ZLIB_URL"
cmake -S "$WORK/zlib" -B "$WORK/zlib/out" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF >/dev/null
cmake --build "$WORK/zlib/out" >/dev/null && cmake --install "$WORK/zlib/out" >/dev/null
# ffmpeg looks for libz.a.
[ -f "$PREFIX/lib/libz.a" ] || cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a" 2>/dev/null || true

echo "== LAME $LAME_VERSION (MP3 encoder library only) =="
unpack lame "$WORK/lame" "$LAME_URL"
(cd "$WORK/lame" && ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-frontend \
    --disable-decoder --disable-dependency-tracking >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

echo "== Opus $OPUS_VERSION =="
unpack opus "$WORK/opus" "$OPUS_URL"
(cd "$WORK/opus" && ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-doc \
    --disable-extra-programs --disable-dependency-tracking >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

echo "== libwebp $WEBP_VERSION (WebP, no image-file dependencies) =="
unpack libwebp "$WORK/libwebp" "$WEBP_URL"
(cd "$WORK/libwebp" && ./configure --prefix="$PREFIX" --disable-shared --enable-static --enable-libwebpmux \
    --disable-libwebpdemux --disable-libwebpdecoder --disable-png --disable-jpeg --disable-tiff --disable-gif \
    --disable-wic --disable-sdl --disable-gl --disable-dependency-tracking >/dev/null && make -j"$JOBS" >/dev/null \
    && make install >/dev/null)

echo "== libaom $AOM_VERSION (AV1, for AVIF photos; the slow one) =="
unpack libaom "$WORK/libaom" "$AOM_URL"
cmake -S "$WORK/libaom" -B "$WORK/libaom/out" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_TOOLS=OFF \
    -DENABLE_TESTDATA=OFF -DCONFIG_AV1_HIGHBITDEPTH=1 >/dev/null
cmake --build "$WORK/libaom/out" >/dev/null && cmake --install "$WORK/libaom/out" >/dev/null

echo "== ffmpeg $FFMPEG_VERSION (LGPL only) =="
unpack ffmpeg "$WORK/ffmpeg" "$FFMPEG_URL"
(cd "$WORK/ffmpeg" && ./configure --prefix="$PREFIX" --arch=x86_64 --target-os=mingw32 \
    --pkg-config-flags=--static --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib -static" \
    --disable-gpl --disable-nonfree --disable-doc --disable-debug --disable-network \
    --disable-autodetect --enable-mediafoundation --enable-w32threads --enable-zlib \
    --disable-programs --enable-ffmpeg --disable-shared --enable-static \
    --enable-libmp3lame --enable-libopus --enable-libwebp --enable-libaom >/dev/null \
    && make -j"$JOBS" >/dev/null)

FF="$WORK/ffmpeg/ffmpeg.exe"
if "$FF" -hide_banner -version | grep -Eq -- '--enable-(gpl|nonfree)'; then
    echo "ffmpeg reports GPL or non-free parts: FAILED" >&2
    exit 1
fi
if ! "$FF" -hide_banner -L | grep -q "Lesser General Public License"; then
    echo "ffmpeg doesn't say it's LGPL: FAILED" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
strip -o "$OUT/ffmpeg.exe" "$FF"
# Each component's licence, shipped with Moss and shown in Settings → Open-source software.
cp "$WORK/ffmpeg/COPYING.LGPLv2.1" "$OUT/ffmpeg-LICENSE.txt"
cp "$WORK/lame/COPYING" "$OUT/lame-LICENSE.txt"
cp "$WORK/opus/COPYING" "$OUT/opus-LICENSE.txt"
cat "$WORK/libwebp/COPYING" "$WORK/libwebp/PATENTS" >"$OUT/libwebp-LICENSE.txt"
cat "$WORK/libaom/LICENSE" "$WORK/libaom/PATENTS" >"$OUT/libaom-LICENSE.txt"
cp "$WORK/zlib/LICENSE" "$OUT/zlib-LICENSE.txt"
# The MinGW-w64 runtime parts linked into ffmpeg.exe (thread and C runtime support).
WINPTHREADS_COPYING="$(cygpath -u "$(dirname "$(command -v gcc)")/../share/licenses/winpthreads/COPYING" 2>/dev/null || true)"
{
    echo "ffmpeg.exe is built with the MinGW-w64 toolchain (GCC). Its runtime support code is under"
    echo "the GCC Runtime Library Exception and the MinGW-w64 runtime licences:"
    echo "https://github.com/mingw-w64/mingw-w64/blob/master/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt"
    [ -f "$WINPTHREADS_COPYING" ] && { echo; cat "$WINPTHREADS_COPYING"; }
} >"$OUT/mingw-w64-runtime-LICENSE.txt"

{
    "$FF" -hide_banner -version
    echo
    echo "Built from source by Apps/Windows/build-ffmpeg.sh (MSYS2 MINGW64, $(gcc --version | head -1))."
    echo "Sources (SHA-256 pinned in the script):"
    echo "  $FFMPEG_URL"
    echo "  $LAME_URL"
    echo "  $OPUS_URL"
    echo "  $WEBP_URL"
    echo "  $AOM_URL"
    echo "  $ZLIB_URL"
    echo "No changes were made to any of these sources."
} >"$OUT/BUILD-INFO.txt"
echo "ffmpeg helper ready in $OUT ($(du -h "$OUT/ffmpeg.exe" | cut -f1), LGPL)"
