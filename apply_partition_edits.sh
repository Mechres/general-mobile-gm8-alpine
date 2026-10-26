#!/bin/bash
set -e
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo mount -o loop,rw "$P/gm8_system_b_mod.img" /tmp/gm8-work/sysmnt
sudo mount -o loop,rw "$P/gm8_vendor_b_mod.img" /tmp/gm8-work/venmnt

echo "--- system/etc/prop.default (before) ---"
grep -nE "adb.secure|usb.config|debuggable" /tmp/gm8-work/sysmnt/etc/prop.default || true
sudo sed -i 's/^persist.sys.usb.config=none$/persist.sys.usb.config=diag,adb/' /tmp/gm8-work/sysmnt/etc/prop.default
echo "--- after ---"
grep -nE "adb.secure|usb.config|debuggable" /tmp/gm8-work/sysmnt/etc/prop.default || true

echo "--- vendor/etc/fstab.qcom system line ---"
grep -n "by-name/system" /tmp/gm8-work/venmnt/etc/fstab.qcom
sudo sed -i '/by-name\/system/s/,verify$//' /tmp/gm8-work/venmnt/etc/fstab.qcom
grep -n "by-name/system" /tmp/gm8-work/venmnt/etc/fstab.qcom

cd /
sudo umount /tmp/gm8-work/sysmnt /tmp/gm8-work/venmnt
echo "DONE - images patched"
