#!/bin/bash
set -e
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${STOCK_ROM_DIR:?set STOCK_ROM_DIR to the unpacked stock QFIL package}"
M=/tmp/gm8-work/finalven
sudo mkdir -p $M; sudo umount $M 2>/dev/null || true
cp "$R/vendor_b" "$P/gm8_vendor_final.img"
sudo mount -o loop,rw "$P/gm8_vendor_final.img" $M
sudo mkdir -p $M/bin/gm8 $M/etc/gm8
sudo cp "$P/vendor_payload/bin/gm8/dropbear"             $M/bin/gm8/dropbear
sudo cp "$P/vendor_payload/etc/gm8/ssh_host_ed25519_key" $M/etc/gm8/
sudo cp "$P/vendor_payload/etc/gm8/authorized_keys"      $M/etc/gm8/
sudo cp "$P/vendor_payload/etc/init/gm8node.rc"          $M/etc/init/
sudo chmod 755 $M/bin/gm8/dropbear
sudo chmod 600 $M/etc/gm8/ssh_host_ed25519_key
sudo chmod 644 $M/etc/gm8/authorized_keys $M/etc/init/gm8node.rc
sudo python3 - <<'PYEOF'
import os
M="/tmp/gm8-work/finalven"
ctx={"bin/gm8/dropbear":b"u:object_r:vendor_file:s0\x00",
     "etc/gm8/ssh_host_ed25519_key":b"u:object_r:vendor_file:s0\x00",
     "etc/gm8/authorized_keys":b"u:object_r:vendor_file:s0\x00",
     "etc/init/gm8node.rc":b"u:object_r:vendor_configs_file:s0\x00"}
for rel,c in ctx.items():
    os.chown(M+"/"+rel,0,0); os.setxattr(M+"/"+rel,b"security.selinux",c)
print("xattrs OK")
PYEOF
cd /; sync; sudo umount $M
echo "READY: gm8_vendor_final.img"
