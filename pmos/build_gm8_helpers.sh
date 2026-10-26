#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-aarch64-linux-musl-gcc}

command -v "$CC" >/dev/null 2>&1 || {
	echo "Missing AArch64 musl compiler: $CC" >&2
	exit 1
}

build_helper()
{
	src=$1
	out=$2
	"$CC" -Os -static -fPIE -pie -s \
		"$SCRIPT_DIR/$src.c" -o "$SCRIPT_DIR/$out"
}

build_helper gm8_reboot_edl gm8_reboot_edl
build_helper gm8_static_init gm8_static_init
build_helper gm8_static_wrapper gm8_static_wrapper
build_helper gm8_wcnss_trigger gm8_wcnss_trigger

echo "GM8 AArch64 helper binaries built with $CC"
