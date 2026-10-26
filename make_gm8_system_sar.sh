#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
P="${GM8_PROJECT_DIR:-$SCRIPT_DIR}"
USER_HOME="${HOME:?HOME must be set}"
TAR="${1:-${GM8_ROOT_TAR:-$USER_HOME/.local/var/pmbootstrap/chroot_buildroot_aarch64/tmp/gm8_sar_root.tar}}"
IMG="${2:-${GM8_OUTPUT_IMAGE:-$P/pmos/images/gm8_system_sar.img}}"
INIT="${3:-${GM8_INIT_OVERLAY:-$P/pmos/gm8_static_wrapper}}"
MNT="${GM8_MOUNT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/gm8-sar.XXXXXX")}"
BUILD_IMG="${IMG}.tmp.$$"
QEMU="$MNT/tmp/qemu-aarch64-static"

usage() {
  echo "Usage: $0 [rootfs-tar] [output-image] [init-overlay]" >&2
}

[ -f "$TAR" ] || {
  echo "MISSING rootfs archive: $TAR" >&2
  usage
  exit 1
}
[ -f "$INIT" ] || { echo "MISSING init overlay: $INIT" >&2; exit 1; }
[ -d "$(dirname -- "$IMG")" ] || {
  echo "MISSING output directory: $(dirname -- "$IMG")" >&2
  exit 1
}

cleanup() {
  rm -f "$QEMU"
  rm -f "$BUILD_IMG"
  if [[ "$MNT" == /tmp/gm8-sar.* ]]; then
    rm -rf "$MNT"
  fi
}
trap cleanup EXIT

mkdir -p "$MNT"
tar xf "$TAR" -C "$MNT"
# The rootfs archive contains BusyBox and its canonical applet manifest, but
# not every symlink normally created by Alpine's apk trigger.  Missing basic
# commands (id, ps, uname, head, ...) also makes several OpenRC scripts fail.
while IFS= read -r applet; do
  [ -n "$applet" ] || continue
  target="$MNT/$applet"
  [ -e "$target" ] || [ -L "$target" ] || ln -s /bin/busybox "$target"
done < "$MNT/etc/busybox-paths.d/busybox"
# Overlay the static PID 1 wrapper that brings up recovery RNDIS/SSH before
# handing control to OpenRC.
install -m755 "$INIT" "$MNT/init"
ln -sf /bin/busybox "$MNT/bin/ash"
install -m644 "$P/pmos/interfaces" \
  "$MNT/etc/network/interfaces"
install -Dm600 "$P/gm8_node_key.pub" \
  "$MNT/root/.ssh/authorized_keys"
install -Dm600 "$P/gm8_node_key.pub" \
  "$MNT/etc/ssh/gm8_authorized_keys"
install -Dm600 "$P/pmos/ssh_host_ed25519_key" \
  "$MNT/etc/ssh/ssh_host_ed25519_key"
install -m755 "$P/pmos/gm8_reboot_edl" "$MNT/usr/sbin/gm8-reboot-edl"

# Qualcomm WCNSS/Pronto Wi-Fi.  The module exactly matches the stock kernel;
# modem_a supplies executable firmware and persist supplies device calibration.
mkdir -p "$MNT/firmware" "$MNT/persist" \
  "$MNT/lib/modules/3.18.120-perf-g5794ae0/extra" \
  "$MNT/lib/firmware/wlan/prima" "$MNT/etc/runlevels/boot"
install -m644 "$P/pmos/fstab" "$MNT/etc/fstab"
install -m644 "$P/pmos/pronto_wlan.ko" \
  "$MNT/lib/modules/3.18.120-perf-g5794ae0/extra/pronto_wlan.ko"
install -m644 "$P/pmos/WCNSS_qcom_cfg.ini" \
  "$MNT/lib/firmware/wlan/prima/WCNSS_qcom_cfg.ini"
ln -sf /persist/WCNSS_qcom_wlan_nv.bin \
  "$MNT/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin"
ln -sf /persist/WCNSS_wlan_dictionary.dat \
  "$MNT/lib/firmware/wlan/prima/WCNSS_wlan_dictionary.dat"
install -m755 "$P/pmos/gm8_wcnss_trigger" "$MNT/usr/sbin/gm8-wcnss-trigger"
install -m755 "$P/pmos/gm8-wifi-hw.initd" "$MNT/etc/init.d/gm8-wifi-hw"
ln -sf /etc/init.d/gm8-wifi-hw "$MNT/etc/runlevels/boot/gm8-wifi-hw"

# APK configuration plus wireless userland.  qemu executes Alpine's native
# aarch64 apk during image construction; it is removed from the final image.
install -m644 "$P/pmos/apk-repositories" "$MNT/etc/apk/repositories"
install -m644 "$P/pmos/resolv.conf" "$MNT/etc/resolv.conf"
install -m755 /usr/bin/qemu-aarch64-static "$QEMU"
set +e
chroot "$MNT" /tmp/qemu-aarch64-static /sbin/apk add --no-cache \
	iw wpa_supplicant wireless-tools
apk_rc=$?
set -e
# This minimal root archive inherits four pre-existing APK database/file audit
# errors from its pmbootstrap build. Treat that status as informational, but
# fail the build if requested package payloads are absent.
for package in iw wpa_supplicant wireless-tools; do
  chroot "$MNT" /tmp/qemu-aarch64-static /sbin/apk info -e "$package"
done
[ -x "$MNT/usr/sbin/iw" ]
[ -x "$MNT/sbin/wpa_supplicant" ]
[ -x "$MNT/usr/sbin/iwconfig" ]
[ "$apk_rc" -eq 0 ] || echo "NOTE: apk reported $apk_rc; requested Wi-Fi packages verified installed"
rm -f "$QEMU"

# Keep credentials out of the image.  This board's protected configuration
# lives on persist, so it also survives a later system_a reflash.
install -m644 "$P/pmos/wpa_supplicant.gm8.conf.d" \
  "$MNT/etc/conf.d/wpa_supplicant"
mkdir -p "$MNT/etc/wpa_supplicant"
ln -sf /persist/gm8-wpa_supplicant.conf \
  "$MNT/etc/wpa_supplicant/wpa_supplicant.conf"
ln -sf /etc/init.d/wpa_supplicant \
  "$MNT/etc/runlevels/boot/wpa_supplicant"
[ ! -x "$MNT/etc/init.d/ntpd" ] || \
  ln -sf /etc/init.d/ntpd "$MNT/etc/runlevels/default/ntpd"

# This phone does not retain RTC time.  Keep the clock within certificate
# validity bounds until wpa_supplicant obtains network access for NTP.
touch "$MNT/etc/gm8-build-time"
install -m755 "$P/pmos/gm8-clock-floor.initd" "$MNT/etc/init.d/gm8-clock-floor"
ln -sf /etc/init.d/gm8-clock-floor "$MNT/etc/runlevels/boot/gm8-clock-floor"

# sanity: SAR init must exist & be executable
[ -x "$MNT/init" ] || { echo "MISSING /init!"; exit 1; }
ls "$MNT/sbin/init" >/dev/null
# Build the ext4 image directly from the completed staging tree.  This avoids
# requiring loop-device privileges while preserving ownership, modes, and
# symlinks from the staged rootfs.
rm -f "$BUILD_IMG"
dd if=/dev/zero of="$BUILD_IMG" bs=1M count=3072 status=none
mkfs.ext4 -F -b 4096 -I 256 \
  -O has_journal,resize_inode,dir_index,filetype,extent,sparse_super,large_file,huge_file,dir_nlink,flex_bg,^64bit,^ext_attr,^extra_isize,^metadata_csum,^metadata_csum_seed,^orphan_file,^quota \
  -L system -d "$MNT" "$BUILD_IMG" >/dev/null
chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$BUILD_IMG"
mv -f "$BUILD_IMG" "$IMG"
trap - EXIT
cleanup
echo "SAR SYSTEM IMAGE READY: $IMG"
