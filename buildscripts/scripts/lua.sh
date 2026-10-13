#!/bin/bash -e

. ../../include/depinfo.sh
. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	make clean
	exit 0
else
	exit 255
fi

# Lua's makefiles do not support out-of-tree builds, so every build starts clean.
$0 clean

# Same recipe as upstream mpv-android: build only liblua.a (LUA_T= LUAC_T=).
# Bionic's localeconv() has no usable decimal_point, so pin it to '.'.
# liolib.c defines _FILE_OFFSET_BITS=64 unless already set; on 32-bit bionic
# that renames fseeko/ftello to the 64-bit variants, which only exist from
# API 24 (we target API 21). Pinning 32 keeps the API-21 symbols and is a
# no-op on 64-bit ABIs, where off_t is always 64-bit.
make CC="$CC" AR="$AR rc" RANLIB="$RANLIB" \
	MYCFLAGS="-fPIC -D_FILE_OFFSET_BITS=32 -Dgetlocaledecpoint\(\)=\(\'.\'\)" \
	PLAT=linux LUA_T= LUAC_T= -j$cores

# TO_BIN=/dev/null skips installing the lua/luac executables.
make INSTALL=${INSTALL:-install} INSTALL_TOP="$prefix_dir" TO_BIN=/dev/null install

# `make pc` prints only the variable block; complete it so meson finds `lua`.
mkdir -p "$prefix_dir/lib/pkgconfig"
make INSTALL_TOP="$prefix_dir" pc >"$prefix_dir/lib/pkgconfig/lua.pc"
cat >>"$prefix_dir/lib/pkgconfig/lua.pc" <<'PC'
Name: Lua
Description: Lua language engine
Version: ${version}
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
PC
