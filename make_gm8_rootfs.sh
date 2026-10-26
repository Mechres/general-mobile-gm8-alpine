#!/bin/bash
set -e
P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT_ROOT="$HOME/.local/var/pmbootstrap/chroot_buildroot_aarch64/gm8root"
IMG="$P/pmos/images/gm8_rootfs.img"
MODVER="3.18.71-perf-g74f4594"

rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count=2560 status=none
mkfs.ext4 -F -L gm8root "$IMG" >/dev/null
mkdir -p /tmp/gm8-work/rfmnt
mount -o loop,rw "$IMG" /tmp/gm8-work/rfmnt

cd "$CHROOT_ROOT"
tar cf - . | tar xf - -C /tmp/gm8-work/rfmnt

mkdir -p /tmp/gm8-work/rfmnt/lib/modules/$MODVER
cd "$P"
tar xf gm8_modules.tar -C /tmp/gm8-work/rfmnt/lib/modules/$MODVER

install -Dm644 "$P/gm8_node_key.pub" /tmp/gm8-work/rfmnt/root/.ssh/authorized_keys
chmod 600 /tmp/gm8-work/rfmnt/root/.ssh/authorized_keys

# wifi firmware from device modem partition will be added later
cd /
umount /tmp/gm8-work/rfmnt
echo "ROOTFS READY: $IMG"
