#!/usr/bin/env bash
# Fushi unified FFmpeg build of libmpv for one ABI.
#
# libmpv links the app's shared FFmpeg (the FFmpegKitNext AAR's lib*.so, built
# by hajisensai/fushi .github/workflows/ffmpeg-unified-mobile.yml) instead of a
# private static FFmpeg, so playback and card mining run on ONE FFmpeg. The
# jar therefore ships only libmpv.so + the media_kit JNI helper; the FFmpeg
# libraries come from the AAR in the same APK.
#
# Usage: bundle_unified.sh <arch> <abi>
set -euo pipefail
cd "$(dirname "$0")"
arch=$1
abi=$2
sdk=$ANDROID_HOME
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$sdk/ndk/27.3.13750724}"
mkdir -p sdk
ln -sfn "$sdk" sdk/android-sdk-linux
chmod +x scripts/*.sh include/*.sh

# The unified FFmpeg dev prefix, pinned by release tag + sha256.
. ./unified-ffmpeg.lock
dev_dir="$PWD/unified-ffmpeg-dev"
mkdir -p "$dev_dir"
tarball="ffmpeg-dev-android-$abi.tar.gz"
want_var="UNIFIED_FFMPEG_SHA256_${abi//-/_}"
want="${!want_var}"
wget -q -O "$dev_dir/$tarball" "$UNIFIED_FFMPEG_RELEASE_URL/$tarball"
echo "$want  $dev_dir/$tarball" | sha256sum -c -
export UNIFIED_FFMPEG_DEV_DIR="$dev_dir"
export UNIFIED_FFMPEG=1

bash -e include/download-deps.sh
bash -e patch.sh
bash -e build.sh --arch "$arch"

out="$PWD/artifacts/unified"
mkdir -p "$out" package
lib="$PWD/prefix/$abi/lib/libmpv.so"
bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
"$bin/llvm-nm" -D "$lib" > "$out/$abi.symbols.txt"
grep -q ' T mpv_lavc_set_java_vm$' "$out/$abi.symbols.txt"
"$bin/llvm-readelf" -h -d -l "$lib" > "$out/$abi.elf.txt"

# Unified FFmpeg: libmpv must NEED the AAR's plain-named FFmpeg libraries and
# must not carry an FFmpeg copy of its own.
for ff in libavcodec libavformat libavutil libavfilter libswresample libswscale; do
    grep -Eq "\(NEEDED\)[[:space:]]+Shared library: \[$ff\.so\]" "$out/$abi.elf.txt" ||
        { echo "libmpv.so does not NEED $ff.so (shared unified FFmpeg)" >&2; exit 3; }
done
# Imports carry the FFmpeg symbol version (avcodec_send_packet@LIBAVCODEC_63).
if grep -Eq ' T (avcodec_send_packet|avformat_open_input|av_log_set_callback)(@|$)' "$out/$abi.symbols.txt"; then
    echo "libmpv.so defines FFmpeg symbols itself: a private FFmpeg was linked in" >&2
    exit 3
fi
grep -Eq ' U avcodec_send_packet(@|$)' "$out/$abi.symbols.txt" ||
    { echo "libmpv.so does not import avcodec_send_packet" >&2; exit 3; }

"$bin/llvm-strings" "$lib" > "$out/$abi.strings.txt"
for capability in discnav disc-navigation-state-json disc-menu-active; do
    grep -Fxq "$capability" "$out/$abi.strings.txt"
done
# Fushi user scripts (mpv Lua) need the Lua backend compiled in.
grep -Fq -- '-Dlua=lua' "$out/$abi.strings.txt"
grep -Fxq 'Lua 5.2' "$out/$abi.strings.txt"
# Fushi BUG-3453 / BUG-3454 mpv patches (dump-cache timestamps).
grep -Fq 'without DefaultDuration' "$out/$abi.strings.txt"
grep -Fq 'Deriving missing DTS' "$out/$abi.strings.txt"

# Reuse the exact shipped helper (not libmpv) so the JNI event loop stays stable.
case "$abi" in
  arm64-v8a) md5=787350dfa246d201a5687e7ac5294004 ;;
  armeabi-v7a) md5=8bbd4ad5d8a2ed97fcfce33e21f0f26b ;;
  x86_64) md5=8bece1e49b609c30da330f8f3deed3e0 ;;
  *) exit 2 ;;
esac
wget -q -O "package/helper-$abi.jar" "https://github.com/hajisensai/hibiki/releases/download/vendor-libmpv/libmpv-android-full-$abi-ffmpeg6.1.6-dovi.jar"
echo "$md5  package/helper-$abi.jar" | md5sum -c -
unzip -q "package/helper-$abi.jar" "lib/$abi/libmediakitandroidhelper.so" -d package
cp "$lib" "package/lib/$abi/libmpv.so"
"$bin/llvm-strip" --strip-unneeded "package/lib/$abi/libmpv.so"
(cd package && zip -qr "$out/full-$abi.jar" "lib/$abi")
python3 - "$out" "$abi" <<'PY'
import hashlib, json, pathlib, subprocess, sys
p = pathlib.Path(sys.argv[1]); abi = sys.argv[2]
jar = p / f'full-{abi}.jar'
provenance = {
    'abi': abi,
    'jar_sha256': hashlib.sha256(jar.read_bytes()).hexdigest(),
    'build_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'mpv_commit': subprocess.check_output(['git', '-C', 'deps/mpv', 'rev-parse', 'HEAD'], text=True).strip(),
    'unified_ffmpeg_lock': pathlib.Path('unified-ffmpeg.lock').read_text(),
    'patches': {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in pathlib.Path('patches/mpv').glob('*.patch')},
}
(p / f'provenance-{abi}.json').write_text(json.dumps(provenance, indent=2) + '\n')
PY
