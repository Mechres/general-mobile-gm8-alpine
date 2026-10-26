#!/usr/bin/env python3
"""Prepare an 'unlocked' copy of a Qualcomm devinfo partition dump.

aboot (GM8 / MSM8940, BOOT.BF.3.x era) reads is_unlocked from the dword at
partition offset 0x10; non-zero => boot image signature verification is
skipped ("Device is unlocked! Skipping verification...").

Usage:
  python3 devinfo_unlock.py <devinfo_orig.bin> <devinfo_out.bin> [--offset 0x10] [--force]

Only writes <devinfo_out.bin>; the input file is never modified.
"""
import argparse
import sys

MAGIC = b"ANDROID-BOOT!"
PART_SIZE = 2048 * 512


def hexdump(buf, start, length):
    for row in range(start, start + length, 16):
        chunk = buf[row:row + 16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print(f"  {row:08x}  {hexs:<47}  |{asc}|")


def main():
    ap = argparse.ArgumentParser(description="Set is_unlocked in a devinfo dump.")
    ap.add_argument("src", help="original devinfo dump (never modified)")
    ap.add_argument("dst", help="output path for patched image")
    ap.add_argument("--offset", default="0x10",
                    help="is_unlocked dword offset (default 0x10; try 0x14 for ver=1 layouts)")
    ap.add_argument("--force", action="store_true",
                    help="proceed even if magic is missing")
    args = ap.parse_args()

    off = int(args.offset, 0)

    with open(args.src, "rb") as f:
        buf = bytearray(f.read())

    print(f"[*] source: {args.src} ({len(buf)} bytes)")
    ok = True
    if len(buf) < PART_SIZE:
        print(f"[!] smaller than partition ({PART_SIZE} B); padding with zeros")
        buf.extend(b"\x00" * (PART_SIZE - len(buf)))
    elif len(buf) > PART_SIZE:
        print(f"[!] larger than partition ({PART_SIZE} B); truncating")
        del buf[PART_SIZE:]

    if bytes(buf[:13]) == MAGIC:
        print("[+] magic 'ANDROID-BOOT!' OK")
    else:
        ok = False
        print("[!] MAGIC MISSING - aboot may treat devinfo as corrupted "
              "(it then demands an erase). Use --force to override.")

    ver = int.from_bytes(buf[0x10:0x14], "little")
    cur = int.from_bytes(buf[off:off + 4], "little")
    print(f"[*] dword@0x10 (unlock flag / possible ver field): {ver}")
    print(f"[*] current value @{args.offset}: {cur}")
    print("[*] head of partition:")
    hexdump(buf, 0, 0x70)

    if cur != 0:
        print(f"[!] @{args.offset} is already non-zero; nothing to do")
        sys.exit(0 if bytes(buf[:13]) == MAGIC else 1)
    if not ok and not args.force:
        print("[!] refusing without --force")
        sys.exit(1)

    orig = bytes(buf)
    buf[off:off + 4] = (1).to_bytes(4, "little")

    with open(args.dst, "wb") as f:
        f.write(buf)

    diffs = [i for i in range(len(orig)) if orig[i] != buf[i]]
    print(f"[+] wrote {args.dst} ({len(buf)} bytes)")
    print(f"[+] changed {len(diffs)} byte(s): "
          + ", ".join(f"{hex(i)}:{orig[i]:02x}->{buf[i]:02x}" for i in diffs))
    print("[+] flash with: edl.py w devinfo " + args.dst)
    print("[!] keep the original dump for restore: edl.py w devinfo " + args.src)


if __name__ == "__main__":
    main()
