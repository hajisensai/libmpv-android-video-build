#!/bin/bash -e
# Fushi unified FFmpeg: libmpv links the SAME FFmpeg shared libraries that the
# app's FFmpegKitNext AAR ships (hajisensai/fushi tool/ffmpeg-unified,
# .github/workflows/ffmpeg-unified-mobile.yml), instead of building and
# statically embedding its own FFmpeg. This step installs that build's
# development prefix (headers + lib*.so + .pc) for the current ABI.
#
# Input: $UNIFIED_FFMPEG_DEV_DIR/ffmpeg-dev-android-<abi>.tar.gz
. ../../include/depinfo.sh
. ../../include/path.sh

case "$1" in
  build) ;;
  clean) exit 0 ;;
  *) exit 255 ;;
esac

: "${UNIFIED_FFMPEG_DEV_DIR:?UNIFIED_FFMPEG_DEV_DIR must point at the ffmpeg-dev-android-*.tar.gz directory}"
abi=$(basename "$prefix_dir")
tarball="$UNIFIED_FFMPEG_DEV_DIR/ffmpeg-dev-android-$abi.tar.gz"
[ -f "$tarball" ] || { echo "missing $tarball" >&2; exit 1; }

rm -rf staging && mkdir staging
tar -xzf "$tarball" -C staging
for lib in libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale; do
	[ -f "staging/lib/$lib.so" ] || { echo "dev prefix lacks $lib.so" >&2; exit 1; }
	[ -f "staging/lib/pkgconfig/$lib.pc" ] || { echo "dev prefix lacks $lib.pc" >&2; exit 1; }
done

mkdir -p "$prefix_dir/include" "$prefix_dir/lib/pkgconfig"
cp -a staging/include/. "$prefix_dir/include/"
cp -a staging/lib/*.so "$prefix_dir/lib/"
# Rewrite the .pc files for this prefix layout (PKG_CONFIG_SYSROOT_DIR is the
# prefix; /usr/local maps back onto it through setup_prefix's symlinks) and
# drop the static-link closure: libmpv links these libraries dynamically, and
# meson's --prefer-static would otherwise demand -lx264 & co.
for pc in staging/lib/pkgconfig/lib*.pc; do
	sed -E \
		-e 's#^prefix=.*#prefix=/usr/local#' \
		-e 's#^exec_prefix=.*#exec_prefix=${prefix}#' \
		-e 's#^libdir=.*#libdir=${prefix}/lib#' \
		-e 's#^includedir=.*#includedir=${prefix}/include#' \
		-e '/^Libs\.private:/d' \
		-e '/^Requires\.private:/d' \
		"$pc" > "$prefix_dir/lib/pkgconfig/$(basename "$pc")"
done
pkg-config --modversion libavcodec
