#!/usr/bin/env python3
"""Surgically splice a modified ramdisk into the stock GM8 boot_b image.

Keeps the ENTIRE original 660-byte boot header verbatim except:
  - ramdisk_size (must change)
  - id[] hash words (zeroed; aboot ignores them in unlocked state)
Optionally appends extra cmdline args (padded with NUL inside 512-byte field).

Usage: python3 boot_splice.py <stock_boot.img> <new_ramdisk.cpio.gz> <out.img> [extra_cmdline]
"""
import gzip
import struct
import sys

PAGE = 2048


def align(x, p=PAGE):
    return (x + p - 1) // p * p


def parse_cpio_entries(cpio):
    assert cpio[:6] == b"070701", "not newc cpio"
    out = []
    i = 0
    while i < len(cpio):
        if cpio[i:i + 6] == b"070702":
            break
        f = {}
        for k in range(13):
            f[k] = int(cpio[i + 6 + k * 8:i + 14 + k * 8], 16)
        namesize = f[11]; filesize = f[6]
        name = cpio[i + 110:i + 110 + namesize - 1]
        dstart = i + 110 + namesize
        dstart = (dstart + 3) & ~3
        data = cpio[dstart:dstart + filesize]
        nxt = (dstart + filesize + 3) & ~3
        out.append((f, name, data))
        i = nxt
    return out


def build_cpio(entries):
    blob = bytearray()
    for f, name, data in entries:
        nf = list(f)
        nf[6] = len(data)
        hdr = b"070701" + b"".join(b"%08X" % v for v in nf)
        nb = name + b"\x00"
        blob += hdr + nb
        blob += b"\x00" * ((-len(blob)) % 4)
        blob += data
        blob += b"\x00" * ((-len(blob)) % 4)
    blob += b"070702" + b"".join(b"%08X" % 0 for _ in range(13))
    blob += b"\x00" * ((-len(blob)) % 4)
    return bytes(blob)


def main():
    stock_path, rd_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    extra = sys.argv[4].encode() if len(sys.argv) > 4 else b""
    setcmdline = sys.argv[5].encode() if len(sys.argv) > 5 else None
    stock = bytearray(open(stock_path, "rb").read())
    PART = len(stock)

    magic = bytes(stock[:8])
    assert magic == b"ANDROID!", "not a boot image"

    ksz, kad, rsz, rad, ssz, sad, tad, pg = struct.unpack_from("<8I", stock, 8)
    assert pg == PAGE, f"unexpected page size {pg}"
    print(f"[i] kernel {ksz} B, ramdisk {rsz} B, page {pg}")

    rd_off = align(PAGE + ksz)
    print(f"[i] ramdisk file offset {hex(rd_off)}")

    new_rd_gz = open(rd_path, "rb").read()

    assert len(new_rd_gz) <= rsz, \
        f"new ramdisk {len(new_rd_gz)} > stock slot {rsz} - cannot splice"
    print(f"[+] new ramdisk {len(new_rd_gz)} B fits in stock slot ({rsz} B)")

    img = bytearray(stock)
    tail_fill = b"\x00" * (PART - rd_off - len(new_rd_gz))
    img[rd_off:] = new_rd_gz + tail_fill

    struct.pack_into("<I", img, 16, len(new_rd_gz))
    struct.pack_into("<8I", img, 0x240, *([0] * 8))

    if setcmdline:
        newcmd = setcmdline[:511]
        field = newcmd + b"\x00" * (512 - len(newcmd))
        img[0x40:0x240] = field
        print("[+] cmdline REPLACED:", newcmd.decode())
    elif extra:
        cmd = bytes(img[0x40:0x240]).split(b"\x00")[0]
        newcmd = (cmd + b" " + extra)[:511]
        field = newcmd + b"\x00" * (512 - len(newcmd))
        img[0x40:0x240] = field
        print(f"[+] cmdline now: {newcmd.decode()}")

    open(out_path, "wb").write(bytes(img))
    print(f"[+] wrote {out_path} ({PART} B)")


if __name__ == "__main__":
    main()
