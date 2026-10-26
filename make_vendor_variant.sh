#!/bin/bash
set -e
# usage: make_vendor_variant.sh <rc|bins|both> <output.img>
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${STOCK_ROM_DIR:?set STOCK_ROM_DIR to the unpacked stock QFIL package}"
MODE="$1"; OUT="$2"
M=/tmp/gm8-work/nodemnt
sudo mkdir -p $M
sudo umount $M 2>/dev/null || true
cp "$R/vendor_b" "$OUT"
sudo mount -o loop,rw "$OUT" $M
printf 'persist.sys.usb.config=diag,adb\nro.adb.secure=0\n' | sudo tee -a $M/default.prop >/dev/null
if [ "$MODE" = "rc" ] || [ "$MODE" = "both" ]; then
  sudo cp "$P/vendor_payload/etc/init/gm8node.rc" $M/etc/init/
  sudo chmod 644 $M/etc/init/gm8node.rc
fi
if [ "$MODE" = "bins" ] || [ "$MODE" = "both" ]; then
  sudo mkdir -p $M/bin/gm8 $M/etc/gm8
  sudo cp "$P/vendor_payload/bin/gm8/dropbear"             $M/bin/gm8/dropbear
  sudo cp "$P/vendor_payload/etc/gm8/ssh_host_ed25519_key" $M/etc/gm8/
  sudo cp "$P/vendor_payload/etc/gm8/authorized_keys"      $M/etc/gm8/
  sudo chmod 755 $M/bin/gm8/dropbear
  sudo chmod 600 $M/etc/gm8/ssh_host_ed25519_key
  sudo chmod 644 $M/etc/gm8/authorized_keys
fi
sudo python3 - <<'PYEOF'
import os,glob
M="/tmp/gm8-work/nodemnt"
targets=[]
if glob.glob(M+"/bin/gm8/dropbear"): targets += ["bin/gm8/dropbear","etc/gm8/ssh_host_ed25519_key","etc/gm8/authorized_keys"]
if glob.glob(M+"/etc/init/gm8node.rc"): targets += ["etc/init/gm8node.rc"]
ctxf=lambda p: b"u:object_r:vendor_configs_file:s0\x00" if "init/" in p else b"u:object_r:vendor_file:s0\x00"
for rel in targets:
    os.chown(M+"/"+rel,0,0)
    os.setxattr(M+"/"+rel,b"security.selinux",ctxf(rel))
print("labeled:",targets)
PYEOF
cd /
sync
sudo umount $M
echo "READY: $OUT"
