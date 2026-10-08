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
meson setup "$build" --cross-file "$prefix_dir/crossfile.txt" \
    --prefer-static -Dvulkan=disabled -Dopengl=enabled -Dd3d11=disabled \
    -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled -Dlibdovi=disabled \
    -Ddovi=enabled -Dunwind=disabled -Dxxhash=disabled -Ddemos=false -Dtests=false
ninja -C "$build" -j"$cores"
DESTDIR="$prefix_dir" ninja -C "$build" install
