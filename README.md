# General Mobile GM 8 — Headless Alpine Linux Node

[![SoC: Qualcomm MSM8940](https://img.shields.io/badge/SoC-Qualcomm%20MSM8940%20(SD435)-blue.svg)](#hardware)
[![Kernel: stock 3.18](https://img.shields.io/badge/Kernel-stock%20Android%203.18-green.svg)](#status)
[![OS: Alpine Linux 3.19](https://img.shields.io/badge/OS-Alpine%20Linux%203.19%20aarch64-purple.svg)](#rebuild-and-flash-the-working-alpine-image)

Reproducible recipe and build tree that turns a screenless **General Mobile GM 8** board (codename `GM8_sprout`) into a headless Alpine Linux node: USB RNDIS networking, root SSH, Qualcomm WCNSS Wi-Fi, working `apk`, and a USB Ethernet option. The board has no battery and no usable display, so everything is done over EDL, fastboot, USB and SSH.

The Alpine userland runs on the **downstream 3.18 Android kernel** (stock; the optional USB Ethernet support uses a patched build) (`system_a` is replaced by an Alpine rootfs, "system-as-root"); the stock Android 9 image stays on `system_b` as a fallback. Only `system_a` is written for the normal workflow.

Detailed engineering notes are in [HANDOFF.md](HANDOFF.md); the open-work checklist is [pmos/notes/REMAINING_WORK.md](pmos/notes/REMAINING_WORK.md).

---

## Hardware

- **Model:** General Mobile GM 8 (`iProduct="GM 8"`, codename `GM8_sprout`)
- **SoC:** Qualcomm **MSM8940** (Snapdragon 435), aarch64 (not the MT6739 GM8 Go)
- **RAM / storage:** 3 GB, 32 GB eMMC
- **Power:** no battery, bench PSU at 4.2 V on the battery terminals
- **Stock kernel:** `3.18.71-perf-g74f4594` (2018), defconfig family `msm8937-perf`; the 2021 Pie vendor image uses `3.18.120-perf-g5794ae0`
- **Bootloader:** LK `BOOT.BF.3.3`, A/B slots, no vbmeta
- **Panel (if ever needed):** HX83102B 720p DSI

## Status

| Feature | State |
|---|---|
| Alpine boot | ✅ Alpine 3.19.9 on `system_a`, stock kernel + OpenRC |
| USB network | ✅ RNDIS `18d1:d002`, device `172.16.42.1/24` |
| SSH | ✅ root key authentication |
| Root filesystem | ✅ ext4, remounted read-write by OpenRC |
| Wi-Fi hardware | ✅ WCNSS online, matching Pronto driver, real AP scans |
| Wi-Fi network | ✅ auto-connect to a configured AP, DHCP, internet and direct SSH |
| Wi-Fi userland | ✅ `iw`, `wpa_supplicant`, `wireless-tools`, NTP |
| APK | ✅ HTTPS `apk update` verified after reboot over Wi-Fi |
| USB Ethernet | ✅ SR9700/9702 adapters; needs the patched kernel in `boot_a` ([USB_ETHERNET.md](pmos/notes/USB_ETHERNET.md)) |
| Android fallback | ✅ stock 9.0 image retained on `system_b` |
| ADB (stock Android path) | ✅ authorized automatically in orange state |
| EDL | ✅ full read/write, button-free re-entry with `adb reboot edl` |
| fastboot | ✅ unlocked (devinfo patch), `fastboot boot <img>` works |
| TWRP rescue | ✅ RAM boot: `fastboot boot 3.6.2_twrp.img` gives a uid 0 adb shell |

Not done: formalising the Wi-Fi setup in a pmbootstrap device package and the mainline kernel path (see [PORT_PLAN.md](pmos/notes/PORT_PLAN.md)).

---

## Key Discoveries

1. **devinfo unlock = master key.** aboot skips boot-image signature
   verification when dword @offset **0x10** of the `devinfo` partition is
   non-zero ("Device is unlocked! Skipping verification..."). Both slot's
   aboots identical. No fastboot/display needed to set it — plain EDL write.
   → after this, ANY boot image boots; `fastboot` reports unlocked.
2. **Orange state auto-authorizes ADB on this device.** With devinfo unlocked,
   even stock user-build ROM gives `adb devices → device` (no RSA tap).
   Mechanism unclear, empirically stable across many boots.
3. **USB composition depends on boot state, not our props.** Stock+locked =
   `18d1:4ee7`; anything orange = userspace falls back to legacy compositions:
   `05c6:f003` (mtp-only) / `9091` (diag+adb) / `f000` (charge mode).
   Editing `persist.sys.usb.config` in vendor `default.prop` (append-only!)
   forces `diag,adb` = `05c6:901D` with adbd — the reliable headless recipe.
4. **No battery ⇒ cold-plug enters CHARGE MODE** (`f000`, skips Android).
   Short-press POWER to proceed. Warm reboots unaffected.
5. **LK honours BCB `bootonce-bootloader` forever if not consumed** → every
   boot lands in fastboot. Fix: zero the whole `misc` partition via EDL.
   Slot retry counters also decay (userspace never marks success headless)
   → both slots "unbootable" → fastboot-only. Fix: `fastboot set_active a`.
6. **Slot roulette:** active slot silently switches after failed retries;
   we once flashed everything to `_b` while `_a` was active. Always check
   `fastboot getvar current-slot`; for experiments flash BOTH slots.
7. **adb reboot bootloader hangs** on stock 8.1 (never reboots).
   `adb reboot edl` WORKS → button-free EDL entry while Android is alive.
8. **The "lineage-18.1-final.zip" is actually OmniROM 9 eng** (mislabelled);
   it boots and gives root trivially, but mixing its system with stock
   vendor/firmware caused confusion. Don't mix ROM families.

## Attempt log (2026-08-23 → 24, condensed)
1. adb unauthorized (no display) → blocked.
2. Modified boot_b → `900e`: aboot verifies boot images (pre-unlock).
3. **devinfo static analysis** (aboot strings + disasm): found unlock gate
   `dword@0x10`. Wrote `devinfo_unlocked.bin` via EDL → verification OFF.
4. Fastboot now available & unlocked; flashed modified boots:
   - AIK-repacked images → silent no-boot (**AIK zeroes header fields**
     `unused@0x2C`, `id[]` that this LK needs — avoid AIK repacks here!).
   - Surgical byte-splice into stock image (`boot_splice.py`) → boots ✓.
5. All modified boots showed `f003` (mtp-only): root-caused to orange-state +
   dead-FDE `/data` (tmpfs fallback) → no persisted props, no adb_enabled.
6. Vendor append-edit (`persist.sys.usb.config=diag,adb` + later dropbear
   payload) via loop-mount + SELinux-xattr-preserving writes → **authorized
   adb achieved** (`<serial> device`). The earlier "vendor breaks boot" claim
   was disproven; real culprit was item 5-slot/bootonce chaos.
7. dropbear (static aarch64, musl, custom-patched: hardcoded `shell`=uid2000,
   `/system/bin/sh` shell, `/vendor/etc/gm8/authorized_keys` path, shell-list
   bypass) → **SSH over USB works** (`adb forward tcp:22222 tcp:2222`).
8. TWRP 3.6.2 discovered RAM-bootable → instant root shell anytime.
9. Full-stock restore performed & verified (both slots md5-identical).

## Rebuild and flash the working Alpine image

Run these commands from this directory on the development host. The explicit paths are intentional: `sudo` may change `HOME` to `/root`.

Prerequisites you must provide (none of them are in this repository):

- the stock QFIL/firehose package for the GM 8 (`prog_emmc_firehose_8940_ddr.mbn` and the original partition images), unpacked at `STOCK_ROM_DIR`
- an EDL client such as [bkerler/edl](https://github.com/bkerler/edl)
- `pmbootstrap`, an aarch64 musl cross compiler, and `pmos/pronto_wlan.ko` extracted from the stock vendor image ([BUILD_INPUTS.md](pmos/notes/BUILD_INPUTS.md))

Generate your own SSH keys (they are git-ignored):

```sh
ssh-keygen -t ed25519 -N '' -f gm8_node_key                    # login key for the node
cp gm8_node_key.pub vendor_payload/etc/gm8/authorized_keys     # only for the stock-Android dropbear path
ssh-keygen -t ed25519 -N '' -f pmos/ssh_host_ed25519_key       # host key baked into the image
ssh-keygen -t ed25519 -N '' -f vendor_payload/etc/gm8/ssh_host_ed25519_key  # stock-Android dropbear path only
```

Build and flash:

```sh
ROOT_TAR="/tmp/gm8_sar_root.repro.tar"
IMAGE="$PWD/pmos/images/gm8_system_sar.img"
INIT="$PWD/pmos/gm8_static_wrapper"

./pmos/build_gm8_helpers.sh
PMBOOTSTRAP=/usr/bin/pmbootstrap \
  ./pmos/build_gm8_root_tar.sh "$ROOT_TAR"
sudo ./make_gm8_system_sar.sh "$ROOT_TAR" "$IMAGE" "$INIT"

# Verify the image before flashing.
file "$IMAGE"
debugfs -R 'stat /init' "$IMAGE"
debugfs -R 'stat /etc/wpa_supplicant/wpa_supplicant.conf' "$IMAGE"
sha256sum "$IMAGE"
```

The hardware-validated reproducible image hash is:

```text
696199acd31a6cad5d07a2454429ea12ad798a55012c3fc94d3521f3ede3a8fb  pmos/images/gm8_system_sar-repro.img
```

The remaining external build inputs and their provenance are listed in
[`pmos/notes/BUILD_INPUTS.md`](pmos/notes/BUILD_INPUTS.md).

With the board in Qualcomm EDL (`05c6:9008`), flash only `system_a`:

```sh
EDL_PY=python
EDL=/path/to/edl/edl.py                       # https://github.com/bkerler/edl
LOADER=/path/to/prog_emmc_firehose_8940_ddr.mbn   # from the stock QFIL package

sudo "$EDL_PY" "$EDL" --loader "$LOADER" w system_a "$IMAGE"
sudo "$EDL_PY" "$EDL" --loader "$LOADER" reset
```

Do not flash `boot`, `vendor`, or `misc` for this workflow. After reset,
confirm USB RNDIS and connect over SSH:

```sh
./setup_gm8_usb_network.sh
ssh -i gm8_node_key root@172.16.42.1
```

The helper defaults to `enp15s0f3u1` and restores the host-side
`172.16.42.2/24` address after a reboot. Pass another interface name as its
first argument if NetworkManager assigns a different name.

Acceptance checks on the node:

```sh
touch /root/acceptance-test && rm /root/acceptance-test
apk update
ip addr show wlan0
ip addr show rndis0
reboot
```

After reboot, reconnect over SSH and verify both interfaces and `apk update`
again. The `sshd [stopped]` entry in `rc-status` is expected: the static
wrapper starts the listener before handing PID 1 to BusyBox/OpenRC.

## Recovery Cookbook
```
# EDL (works even from bootloop/black):
#   PSU cut → hold EDL combo → power (combo as used on bench)
python edl.py --loader <prog_emmc_firehose_8940_ddr.mbn> \
    [printgpt | r <part> out.bin | w <part> in.bin | reset]
# Restore stock boot slots:
edl.py w boot_a "$STOCK_ROM_DIR/boot_a" ; same for boot_b
# Clear stuck fastboot-loop: w misc zeros(1MiB)
# Re-unlock: python3 devinfo_unlock.py devinfo_orig.bin out && w devinfo out

# fastboot path (from running Android): adb reboot bootloader may HANG on
# stock 8.1 — use button combo (PSU cut + VOL-DOWN held + power) instead.
fastboot set_active a            # resets decayed retry counters
fastboot continue                # resume normal boot from fastboot shell
fastboot boot <img>              # risk-free RAM boot
```

---

## Repository Layout

```
HANDOFF.md                  engineering notes: verified facts, recipes, traps
setup_gm8_usb_network.sh    host side of the RNDIS link (172.16.42.2/24)
devinfo_unlock.py           sets the is_unlocked dword in `devinfo`
boot_splice.py              surgical ramdisk splice into a stock boot image
replace_boot_kernel.py      swap the kernel inside a stock boot image
apply_*.sh, make_*.sh       vendor/system image builders (stock-Android path and Alpine SAR)
vendor_payload/             dropbear service definition for the stock-Android SSH node
pmos/                       Alpine/postmarketOS port: init wrapper, helpers, kernel patches, notes
pmos/device/*.patch         device tree and USB Ethernet kernel patches (GPL-2.0)
pmos/notes/                 PORT_PLAN, DEVICE_FACTS, BUILD_INPUTS, USB_ETHERNET, REMAINING_WORK
```

Firmware, ROM packages, disk images, vendored kernel trees, TWRP trees and all private keys are excluded by `.gitignore` and must be supplied locally.

## Safety Notes

- Always check `fastboot getvar current-slot` before flashing, or flash both slots.
- Do not use AIK-style repacks for this bootloader; use `boot_splice.py`.
- Keep a stock backup of `boot_a`/`boot_b`/`system_a` before any write.
- Never commit Wi-Fi credentials, private keys or the `persist` partition contents.

## License

Scripts, helpers and documentation are available under the MIT License (see [LICENSE](LICENSE)). The kernel and device tree patches under `pmos/device/` are licensed under GPL-2.0, like the kernel they modify. Stock firmware, vendor modules and ROM packages belong to their respective owners and are not included.
