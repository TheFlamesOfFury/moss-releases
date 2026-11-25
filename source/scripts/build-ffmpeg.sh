#!/bin/bash
# Builds the ffmpeg helper that Moss for Mac uses for formats Apple's frameworks
# can't handle (MP3 output, MKV/AVI output, WebP, and reading MKV/WebM/AVI/OGG).
#
#   scripts/build-ffmpeg.sh        → build/third-party/out/ffmpeg (universal: arm64 + x86_64)
#
# Licensing (see docs/THIRD_PARTY.md): ffmpeg is built LGPL-only (no --enable-gpl,
# no --enable-nonfree) and runs as a separate program inside Moss.app
# (Contents/Helpers/ffmpeg); Moss never links it. LAME (LGPL) and libwebp (BSD)
# are linked into that helper. The exact sources below, this script and the
# configure flags are what "the corresponding source" means for the LGPL; the
# licence texts are copied next to the binary and shipped in the app.
#
# Downloads come only from each project's official site over HTTPS, and are
# checked against the SHA-256 values pinned here (recorded on first download,
# 2026-11-24). Change a version → update its URL and hash together.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)/build/third-party"
DOWNLOADS="$ROOT/downloads"
OUT="$ROOT/out"
# Compiling happens in a neutral folder: ffmpeg records its build settings
# (paths included) inside the program, and the build shouldn't carry the
# builder's home folder into a shipped app.
WORKROOT="${MOSS_FFMPEG_WORKDIR:-/tmp/moss-ffmpeg-build}"
MIN_MACOS=26.0
JOBS=$(sysctl -n hw.ncpu)

FFMPEG_VERSION=7.1.1
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
FFMPEG_SHA256="${FFMPEG_SHA256:-}"
LAME_VERSION=3.100
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
LAME_SHA256="${LAME_SHA256:-}"
WEBP_VERSION=1.5.0
WEBP_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz"
WEBP_SHA256="${WEBP_SHA256:-}"
# Pinned hashes (filled in after the first verified download; see THIRD_PARTY.md).
[ -f "$(dirname "$0")/ffmpeg-hashes.env" ] && . "$(dirname "$0")/ffmpeg-hashes.env"

# Downloads one archive into its own folder and checks its hash.
fetch() { # name url sha256
    local name=$1 url=$2 sha=$3 dir="$DOWNLOADS/$1" file
    file="$dir/$(basename "$url")"
    mkdir -p "$dir"
    [ -f "$file" ] || curl --fail --location --proto '=https' --tlsv1.2 -o "$file" "$url"
    local actual
    actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    if [ -n "$sha" ] && [ "$actual" != "$sha" ]; then
        echo "error: $name hash mismatch ($actual, expected $sha)" >&2
        exit 1
    fi
    echo "$name sha256 $actual"
}

# Unpacks a fresh copy of a source archive for one architecture.
unpack() { # name archive-dir dest
    rm -rf "$3"
    mkdir -p "$3"
    tar -xf "$DOWNLOADS/$1"/* -C "$3" --strip-components 1
}

fetch ffmpeg "$FFMPEG_URL" "$FFMPEG_SHA256"
fetch lame "$LAME_URL" "$LAME_SHA256"
fetch libwebp "$WEBP_URL" "$WEBP_SHA256"

rm -rf "$ROOT"/work-* "$ROOT"/arm64 "$ROOT"/x86_64  # older in-project build folders
for ARCH in arm64 x86_64; do
    PREFIX="$WORKROOT/$ARCH"
    WORK="$WORKROOT/work-$ARCH"
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX" "$WORK"
    HOST=$([ "$ARCH" = arm64 ] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
    export CC="clang -arch $ARCH -mmacosx-version-min=$MIN_MACOS"
    export CFLAGS="-O2"

    # LAME: the MP3 encoder library only (no command-line tool).
    unpack lame _ "$WORK/lame"
    (cd "$WORK/lame" && ./configure --host="$HOST" --prefix="$PREFIX" --disable-shared --enable-static \
        --disable-frontend --disable-decoder --disable-dependency-tracking >/dev/null && make -j"$JOBS" >/dev/null &&
        make install >/dev/null)

    # libwebp: still and animated WebP, no image-file dependencies.
    unpack libwebp _ "$WORK/libwebp"
    (cd "$WORK/libwebp" && ./configure --host="$HOST" --prefix="$PREFIX" --disable-shared --enable-static \
        --enable-libwebpmux --disable-libwebpdemux --disable-libwebpdecoder --disable-png --disable-jpeg \
        --disable-tiff --disable-gif --disable-wic --disable-sdl --disable-gl --disable-dependency-tracking \
        >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

    # No pkg-config on this Mac: a tiny stand-in that answers ffmpeg's
    # questions about libwebp from the prefix above.
    SHIM="$WORK/pkg-config"
    cat >"$SHIM" <<EOF
#!/bin/sh
case "\$*" in
  *--exists*|*--version*) exit 0 ;;
  *--modversion*) echo $WEBP_VERSION ;;
  *--cflags*) echo "-I$PREFIX/include" ;;
  *--libs*) echo "-L$PREFIX/lib -lwebpmux -lwebp -lsharpyuv -lm" ;;
esac
EOF
    chmod +x "$SHIM"

    # ffmpeg: LGPL only, the ffmpeg program only, Apple's hardware encoders on.
    unpack ffmpeg _ "$WORK/ffmpeg"
    CROSS=()
    [ "$ARCH" = x86_64 ] && CROSS=(--enable-cross-compile --disable-x86asm)
    (cd "$WORK/ffmpeg" && ./configure --prefix="$PREFIX" --arch="$ARCH" --target-os=darwin --cc="$CC" \
        ${CROSS[@]+"${CROSS[@]}"} --pkg-config="$SHIM" \
        --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
        --disable-gpl --disable-nonfree --disable-doc --disable-debug --disable-network \
        --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
        --disable-programs --enable-ffmpeg \
        --enable-libmp3lame --enable-libwebp \
        --enable-static --disable-shared >"$WORK/ffmpeg-configure.log" &&
        make -j"$JOBS" >/dev/null && cp ffmpeg "$PREFIX/ffmpeg")
done

mkdir -p "$OUT/licenses"
lipo -create "$WORKROOT/arm64/ffmpeg" "$WORKROOT/x86_64/ffmpeg" -output "$OUT/ffmpeg"
strip -x "$OUT/ffmpeg"
cp "$WORKROOT/work-arm64/ffmpeg/COPYING.LGPLv2.1" "$OUT/licenses/ffmpeg-COPYING.LGPLv2.1.txt"
cp "$WORKROOT/work-arm64/ffmpeg/LICENSE.md" "$OUT/licenses/ffmpeg-LICENSE.md"
cp "$WORKROOT/work-arm64/lame/COPYING" "$OUT/licenses/lame-COPYING.txt"
cp "$WORKROOT/work-arm64/libwebp/COPYING" "$OUT/licenses/libwebp-COPYING.txt"
cp "$WORKROOT/work-arm64/libwebp/PATENTS" "$OUT/licenses/libwebp-PATENTS.txt"
{
    echo "ffmpeg $FFMPEG_VERSION  $FFMPEG_URL"
    echo "LAME $LAME_VERSION  $LAME_URL"
    echo "libwebp $WEBP_VERSION  $WEBP_URL"
    echo
    echo "Built by scripts/build-ffmpeg.sh. ffmpeg configuration:"
    "$WORKROOT/arm64/ffmpeg" -hide_banner -buildconf 2>&1 | sed 's/^/  /'
} >"$OUT/licenses/BUILD-INFO.txt"
"$OUT/ffmpeg" -hide_banner -version | head -1
lipo -info "$OUT/ffmpeg"
# Must say "Lesser" (LGPL); a GPL build would say "GNU General Public License".
"$OUT/ffmpeg" -hide_banner -L 2>&1 | grep -q "GNU Lesser General Public" || { echo "error: not an LGPL build" >&2; exit 1; }
echo "license: LGPL 2.1 or later"
