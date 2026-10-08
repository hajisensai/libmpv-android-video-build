#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
arch=$1
abi=$2
sdk=$ANDROID_HOME
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$sdk/ndk/25.2.9519653}"
mkdir -p sdk
ln -s "$sdk" sdk/android-sdk-linux
chmod +x scripts/*.sh include/*.sh
bash -e include/download-deps.sh
bash -e patch.sh
cp flavors/full.sh scripts/ffmpeg.sh
chmod +x scripts/ffmpeg.sh
bash -e build.sh --arch "$arch"

out="$PWD/artifacts/disc-menu"
mkdir -p "$out" package
lib="$PWD/prefix/$abi/lib/libmpv.so"
bin="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
"$bin/llvm-nm" -D "$lib" > "$out/$abi.symbols.txt"
grep -q ' T mpv_lavc_set_java_vm$' "$out/$abi.symbols.txt"
"$bin/llvm-strings" "$lib" > "$out/$abi.strings.txt"
for capability in discnav disc-navigation-state-json disc-menu-active; do
    grep -Fxq "$capability" "$out/$abi.strings.txt"
done
"$bin/llvm-readelf" -h -d -l "$lib" > "$out/$abi.elf.txt"
# Reuse the exact shipped helper (not libmpv) so the JNI event loop stays stable.
case "$abi" in
  arm64-v8a) md5=787350dfa246d201a5687e7ac5294004 ;;
  armeabi-v7a) md5=8bbd4ad5d8a2ed97fcfce33e21f0f26b ;;
  x86_64) md5=8bece1e49b609c30da330f8f3deed3e0 ;;
  x86) md5=289c82b7438ec75f8808d2c1443c9ffe ;;
  *) exit 2 ;;
esac
wget -O "package/helper-$abi.jar" "https://github.com/hajisensai/hibiki/releases/download/vendor-libmpv/libmpv-android-full-$abi-ffmpeg6.1.6-dovi.jar"
echo "$md5  package/helper-$abi.jar" | md5sum -c -
unzip -q "package/helper-$abi.jar" "lib/$abi/libmediakitandroidhelper.so" -d package
cp "$lib" "package/lib/$abi/libmpv.so"
"$bin/llvm-strip" --strip-unneeded "package/lib/$abi/libmpv.so"
(cd package && zip -qr "$out/full-$abi.jar" "lib/$abi")
python3 - "$out" <<'PY'
import hashlib, json, pathlib, subprocess, sys
p = pathlib.Path(sys.argv[1])
checksums = {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in p.glob('full-*.jar')}
(p/'sha256.json').write_text(json.dumps(checksums, indent=2)+'\n')
provenance = {
    'build_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'mpv_commit': subprocess.check_output(['git', '-C', 'deps/mpv', 'rev-parse', 'HEAD'], text=True).strip(),
    'patches': {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in pathlib.Path('patches/mpv').glob('*.patch')},
}
(p/'provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
PY
