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
# mpv links with the C driver. The static libplacebo archive contains C++
# charconv code but its generated pkg-config file omits the C++ runtime.
# Keep that runtime private/static, avoiding an unbundled libc++_shared.so.
printf '\nLibs.private: -lc++_static -lc++abi -lunwind\n' >> "$prefix_dir/lib/pkgconfig/libplacebo.pc"
