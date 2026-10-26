#!/bin/bash
set -e
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${STOCK_ROM_DIR:?set STOCK_ROM_DIR to the unpacked stock QFIL package}"
mkdir -p /tmp/gm8-work/venmnt
cp "$R/vendor_b" "$P/gm8_vendor_b_prop.img"
sudo mount -o loop,rw "$P/gm8_vendor_b_prop.img" /tmp/gm8-work/venmnt
echo 'persist.sys.usb.config=diag,adb' | sudo tee -a /tmp/gm8-work/venmnt/default.prop
tail -3 /tmp/gm8-work/venmnt/default.prop
cd /
sudo umount /tmp/gm8-work/venmnt
echo "OK: gm8_vendor_b_prop.img patched"
