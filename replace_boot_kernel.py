#!/usr/bin/env python3
"""Replace the kernel payload in an Android boot image without flashing it."""

import struct
import sys
import zlib
from pathlib import Path

PAGE = 2048
HEADER = 0x240


def align(value: int) -> int:
    return (value + PAGE - 1) & ~(PAGE - 1)


def gzip_stream_and_tail(payload: bytes) -> tuple[bytes, bytes]:
    """Split a gzip-compressed kernel from the appended Qualcomm DTBs."""
    stream = zlib.decompressobj(16 + zlib.MAX_WBITS)
    stream.decompress(payload)
    if not stream.eof:
        raise ValueError("kernel payload is not a complete gzip stream")
    return payload[: len(payload) - len(stream.unused_data)], stream.unused_data


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} <base-boot.img> <kernel> <output.img>")

    base_path, kernel_path, output_path = map(Path, sys.argv[1:])
    base = bytearray(base_path.read_bytes())
    supplied_kernel = kernel_path.read_bytes()

    if bytes(base[:8]) != b"ANDROID!":
        raise SystemExit("base image is not an Android boot image")

    kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr, tags_addr, page = struct.unpack_from(
        "<8I", base, 8
    )
    if page != PAGE:
        raise SystemExit(f"unsupported page size: {page}")
    if second_size:
        raise SystemExit("base image has a second-stage payload; refusing to rewrite it")

    base_kernel = bytes(base[PAGE : PAGE + kernel_size])
    _, stock_dtbs = gzip_stream_and_tail(base_kernel)
    new_gzip, supplied_dtbs = gzip_stream_and_tail(supplied_kernel)
    if not stock_dtbs:
        raise SystemExit("base image has no appended Qualcomm DTBs")
    if supplied_dtbs and len(supplied_dtbs) != len(stock_dtbs):
        raise SystemExit("supplied kernel has a different DTB bundle size")
    kernel = new_gzip + stock_dtbs

    old_ramdisk_offset = align(PAGE + kernel_size)
    new_ramdisk_offset = align(PAGE + len(kernel))
    if old_ramdisk_offset + ramdisk_size > len(base):
        raise SystemExit("base ramdisk extends beyond the image")
    if new_ramdisk_offset + ramdisk_size > len(base):
        raise SystemExit("new kernel and existing ramdisk do not fit in the image")

    ramdisk = bytes(base[old_ramdisk_offset : old_ramdisk_offset + ramdisk_size])
    image = bytearray(len(base))
    image[:PAGE] = base[:PAGE]
    image[PAGE : PAGE + len(kernel)] = kernel
    image[new_ramdisk_offset : new_ramdisk_offset + ramdisk_size] = ramdisk
    struct.pack_into("<I", image, 8, len(kernel))
    # The GM8 is already unlocked; match the project's proven boot-splice images.
    image[HEADER : HEADER + 32] = b"\0" * 32

    output_path.write_bytes(image)
    print(f"kernel: {kernel_size} -> {len(kernel)} bytes")
    print(f"ramdisk: {ramdisk_size} bytes at 0x{new_ramdisk_offset:x}")
    print(f"wrote: {output_path} ({len(image)} bytes)")


if __name__ == "__main__":
    main()
