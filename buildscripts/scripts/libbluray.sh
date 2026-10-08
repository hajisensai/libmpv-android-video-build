#!/bin/bash -e
. ../../include/depinfo.sh
. ../../include/path.sh
build=_build$ndk_suffix
case "$1" in
  build) ;;
  clean) rm -rf "$build"; exit 0 ;;
  *) exit 255 ;;
esac
unset CC CXX
# Android's ART is not a desktop JVM. Build HDMV/ISO navigation without
# advertising BD-J availability; libbluray reports JVM absence at runtime.
meson setup "$build" --cross-file "$prefix_dir/crossfile.txt" \
    --prefer-static -Dbdj_jar=disabled -Denable_tools=false \
    -Dfontconfig=disabled -Dfreetype=enabled -Dlibxml2=enabled
ninja -C "$build" -j"$cores"
DESTDIR="$prefix_dir" ninja -C "$build" install
