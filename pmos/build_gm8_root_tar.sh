#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
USER_HOME=${HOME:?HOME must be set}
if [ -n "${PMBOOTSTRAP:-}" ]; then
    :
else
    PMBOOTSTRAP=$(command -v pmbootstrap || true)
fi
CHROOT_ROOT=${PMBOOTSTRAP_CHROOT_ROOT:-$USER_HOME/.local/var/pmbootstrap/chroot_buildroot_aarch64}
OUTPUT=${1:-$PROJECT_DIR/gm8_sar_root.tar}

[ -n "$PMBOOTSTRAP" ] && command -v "$PMBOOTSTRAP" >/dev/null 2>&1 || {
    echo "Missing pmbootstrap: $PMBOOTSTRAP" >&2
    exit 1
}

case "$OUTPUT" in
    /*) ;;
    *) OUTPUT="$PWD/$OUTPUT" ;;
esac

ROOT=/gm8root-repro
CHROOT_ARCHIVE=/tmp/gm8_sar_root.repro.tar
mkdir -p "$(dirname -- "$OUTPUT")"

"$PMBOOTSTRAP" chroot -b aarch64 -- sh -s <<'EOF'
set -eu
R=/gm8root-repro
OUT=/tmp/gm8_sar_root.repro.tar

rm -rf "$R"
rm -f "$OUT"
mkdir -p "$R"

# Package scripts use unshare/user namespaces and fail under QEMU user
# emulation. Install payloads without scripts and configure runlevels below.
APK_INDEX=
if [ -d /mnt/pmbootstrap-packages ]; then
    APK_INDEX=$(find /mnt/pmbootstrap-packages -type f -name APKINDEX.tar.gz -print -quit)
fi
if [ -n "$APK_INDEX" ]; then
    APK_REPO=${APK_INDEX%/APKINDEX.tar.gz}
    apk -X "$APK_REPO" \
      --allow-untrusted --root "$R" --initdb --arch aarch64 \
      add --no-scripts alpine-base openssh openrc eudev kmod busybox mdev-conf
else
    apk -X https://dl-cdn.alpinelinux.org/alpine/edge/main \
      -X https://dl-cdn.alpinelinux.org/alpine/edge/community \
      --allow-untrusted \
      --root "$R" --initdb --arch aarch64 \
      add --no-scripts alpine-base openssh openrc eudev kmod busybox mdev-conf
fi

mkdir -p "$R/etc/network" "$R/root/.ssh" \
  "$R/etc/runlevels/sysinit" "$R/etc/runlevels/boot" \
  "$R/etc/runlevels/default" "$R/etc/runlevels/shutdown"
printf 'GM8-node\n' > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n172.16.42.1\tgm8\n' > "$R/etc/hosts"

sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' \
  "$R/etc/ssh/sshd_config" 2>/dev/null || true

for service in devfs dmesg mdev hwdrivers; do
    [ -e "$R/etc/init.d/$service" ] && \
        ln -sf "/etc/init.d/$service" "$R/etc/runlevels/sysinit/$service"
done
for service in modules hwclock swap hostname sysctl bootmisc syslog networking; do
    [ -e "$R/etc/init.d/$service" ] && \
        ln -sf "/etc/init.d/$service" "$R/etc/runlevels/boot/$service"
done
[ ! -e "$R/etc/init.d/local" ] || \
    ln -sf /etc/init.d/local "$R/etc/runlevels/default/local"

cd "$R"
tar cf "$OUT" .
EOF

[ -f "$CHROOT_ROOT$CHROOT_ARCHIVE" ] || {
    echo "pmbootstrap did not produce $CHROOT_ROOT$CHROOT_ARCHIVE" >&2
    exit 1
}

sudo cp "$CHROOT_ROOT$CHROOT_ARCHIVE" "$OUTPUT"
sudo chown "$(id -u):$(id -g)" "$OUTPUT"
sudo rm -f "$CHROOT_ROOT$CHROOT_ARCHIVE"
echo "GM8 ROOTFS ARCHIVE READY: $OUTPUT"
