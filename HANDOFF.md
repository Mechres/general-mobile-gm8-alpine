# GM8_sprout HEADLESS PORT — AGENT HANDOFF (2026-08-26)

Read this fully before touching anything. It supersedes guesses; every claim
below was empirically established on the real board unless marked hypothesis.

---

## 0. RESOLVED CURRENT STATE (2026-08-26)

The headless Alpine target is now **working on the real GM8**:

- `system_a` boots Alpine Linux 3.19.9 using the stock 3.18.120 Android kernel.
- PID 1 is `/sbin/init` (BusyBox init) and OpenRC reaches the default runlevel.
- Legacy `android_usb` enumerates RNDIS as USB `18d1:d002`.
- Device interface is `rndis0`, statically addressed `172.16.42.1/24`.
- Root SSH key authentication works with `gm8_node_key`.
- Root ext4 is remounted read-write by OpenRC; an actual create/remove test in
  `/root` succeeded.
- Hostname is `GM8-node`; standard BusyBox commands (`id`, `uname`, `ps`, etc.)
  are present and work without a `/bin/busybox` prefix.
- A normal `reboot` issued over SSH was tested: the board re-enumerated as
  RNDIS and root SSH returned without EDL or physical intervention.
- Qualcomm WCNSS/Pronto Wi-Fi is working.  `gm8-wifi-hw` mounts stock
  `modem_a` firmware and `persist` calibration, starts WCNSS, and loads the
  exact-kernel `pronto_wlan.ko`; it reaches `WCNSS=ONLINE` at every boot.
- `wlan0` is created and real AP scans succeed; the final post-flash scan listed
  the neighbouring access points.
- `iw`, `wpa_supplicant`, and `wireless-tools` are installed.  APK main and
  community repositories work; the final `apk update` indexed 22,897
  packages.  No SSID/passphrase is baked into the image.
- The phone is configured to auto-connect to a test access point.  A
  post-configuration cold reboot proved WPA association, DHCP,
  direct Wi-Fi SSH, internet, NTP, and `apk update` all return automatically.
  The protected WPA file is mode `0600` at
  `/persist/gm8-wpa_supplicant.conf`; `/etc/wpa_supplicant/wpa_supplicant.conf`
  is a symlink to it.  The passphrase is not present in this repository or
  the system image and must never be added to either.
- The board RTC resets to 1970, so `gm8-clock-floor` raises it to image build
  time before networking; this keeps APK HTTPS certificate validation usable.

Host connection recipe (current host interface name):

```sh
./setup_gm8_usb_network.sh <host-usb-interface>   # sets the host side to 172.16.42.2/24
ssh -i gm8_node_key root@172.16.42.1
```

Final image and wrapper hashes:

```text
4a9a41261e8f80c1aa7423a52bcfe8c7afb9e312dc3d70c0e568c89bab6007f8  pmos/images/gm8_system_sar.img
69f3cae2371ea86ae5df0aef16592ad5bf4b01a721cff5f927d3675fc0282927  pmos/gm8_static_wrapper
792b4afe99710bba26137106da97ff0bff03057f89e344fd5a0d83ad10faf052  pmos/pronto_wlan.ko
```

The decisive findings were:

1. A static AArch64 `/init` wrote `GM8_STATIC_RAN1` to `misc`, proving the
   kernel mounted `system_a` and executed userspace. The vibration-only test
   was misleading because it targeted the wrong downstream API.
2. A static PID-1 wrapper proved the musl loader and dynamic BusyBox worked,
   then configured legacy `android_usb` RNDIS and launched sshd directly.
3. `/bin/ash` was absent, so successful SSH authentication could not launch
   root's configured shell. The image builder now creates that link.
4. The Alpine archive had BusyBox but omitted most applet links. The builder
   now reconstructs all missing links from
   `/etc/busybox-paths.d/busybox`, allowing OpenRC to complete.
5. The original network config named `usb0`, while this kernel creates
   `rndis0`. `/etc/network/interfaces` now uses `rndis0`. A small `/init`
   child also reapplies the management address every five seconds because
   mdev/OpenRC may cycle the interface during early boot.
6. The matching WLAN module came from the February 2021 stock Pie vendor
   image.  Its vermagic is exactly `3.18.120-perf-g5794ae0 SMP preempt
   mod_unload modversions aarch64`; the older 2018 vendor module does not
   match and must not be used.
7. WCNSS must be triggered by keeping `/dev/wcnss_wlan` open after setting
   the firmware-class path to `/firmware/image`, then the module may be
   inserted.  Firmware lives on `modem_a` (`mmcblk0p1`) and calibration on
   `persist` (`mmcblk0p29`).

`rc-status` reports the OpenRC `sshd` service as stopped because the static
wrapper deliberately starts sshd before handing PID 1 to BusyBox init. The
actual sshd listener is alive and verified. This is a bookkeeping issue, not
an access failure.

---

## 1. ORIGINAL PROBLEM (resolved; retained for investigation history)

Boot chain: stock GM8 kernel (3.18.71-perf, both slots untouched) +
LK-appended args `skip_initramfs rootwait ro init=/init root=/dev/mmcblk0p25`
+ `system_a` partition containing an **Alpine Linux rootfs with a `/init`
shell shim**.

**Observed:** board powers, draws steady 0.06–0.10 A forever, NO USB
enumeration of any kind, NO reboots, NO vibration markers (but see §5 —
vibration test may be invalid), stays that way for many minutes.

**Expected:** `/init` shim runs (mounts, pulses vibrator, pets watchdog,
execs /sbin/init → OpenRC → sshd + RNDIS gadget).

**Interpretations (pick one and prove it):**
- (a) Kernel mounts p25, execs `/init`, shim HANGS early (before 1st buzz —
      but buzz code may itself be broken, see §5.1)
- (b) Kernel can't exec `/init` (ENOENT/ENOEXEC) → panic("no working init")
      → with `panic_timeout=0` it HANGS instead of rebooting ✓ also fits!
      (LK leaves watchdog disabled; nothing resets it)
- (c) Root mount itself fails ("Unable to mount root fs") → same hang ✓ fits
- (d) LK passes extra args we haven't accounted for (dumped cmdlines show it
      appends a LOT after our header cmdline)

Distinguishing experiment ideas:
1. Put a STATIC binary as `/init` (not a #!/bin/sh script — removes
   interpreter dependency): e.g., copy busybox itself to /init with a wrapper
   impossible — instead compile 20-line static aarch64 hello that blinks the
   vibrator LED class via write(), or simply forks `while(1) pause();` while
   setting up configfs-RNDIS *in C*. If static /init runs → script env issue;
   if not → exec/mount layer issue.
2. Replace Alpine rootfs with **the original Android system_a image** (keep
   everything else identical): if Android boots again → exec/mount of foreign
   rootfs is the issue; if Android ALSO hangs now → something else about the
   current flash state is broken (userdata? misc? devinfo?) — sanity-check!
3. Wire a USB-UART adapter to the board's serial pads (ttyHSL0 @115200,
   msm_hsl earlycon @0x78B0000). This ends all guessing. GM8 pad-out likely
   findable in GM8_sprout TWRP/kernel repos or by continuity-probing the
   MSM8937-MTP reference pinout.

## 2. VERIFIED BOARD FACTS
- SoC MSM8940 (SD435), aarch64, 3 GB RAM, eMMC 32 GB, **no battery**
  (bench PSU ~4.2 V; USB also attached). Cold-plug w/o buttons = charge mode
  (`f000`) unless POWER tapped; warm reboots normal.
- Bootloader LK `BOOT.BF.3.3`; A/B; `skip_initramfs` IS appended by LK on
  normal boots (system-as-root). LK also selects DTB `qcom,msm8940-mtp`
  (msm-id 0x139, board-id 0x8) — relevant only to mainline attempts.
- Stock partitions: system_a=p25, system_b=p26, misc=p30, userdata=p52
  (full map: `pmos/notes/DEVICE_FACTS.md` + EDL printgpt).
- Stock kernel: no /proc/config.gz, NO pstore/ramoops strings, HAS
  `qcom,msm-watchdog`, HAS legacy `android_usb` class (all observed
  compositions f000/f003/9091/4ee7 driven through it), gadget modules NOT
  modular (built-in).
- devinfo dword@0x10=1 (unlocked) currently flashed → aboot skips boot
  signature verification ("Device is unlocked! Skipping verification...").
- Orange/unlocked state auto-authorizes ADB on stock ROMs (no RSA tap).
- `adb reboot bootloader` HANGS on stock 8.1 (never reboots).
  `adb reboot edl` WORKS (button-free EDL while Android alive).
- `adb reboot edl` + `edl.py reset` sometimes leaves board USB-silent →
  cold PSU cycle fixes.
- LK disables/stops petting watchdog pre-jump: kernel panics HANG (no auto
  reset) — confirmed by non-looping hangs.

## 3. WHAT WORKED BEFORE (proven recipes)
### 3.1 Authorized ADB + dropbear SSH node (STOCK Android path) ✅ DONE
- Flash `devinfo_unlocked.bin` (EDL) → verification off, orange state,
  adb authorized automatically.
- For root: use `gm8s_D_root.img` (surgical splice: stock boot_b bytes +
  ramdisk prop.default edits ro.secure=0/adb.secure=0/debuggable=1) — built
  by `boot_splice.py`. DO NOT use AIK-Linux repacks: AIK zeroes boot-header
  fields (unused@0x2C, id[]) this LK requires → silent no-boot.
- dropbear: static aarch64 musl build with patches (hardcoded shell user
  uid2000, pw_shell=/system/bin/sh, authkeys path /vendor/etc/gm8/, getusershell
  bypass). Binary + keys + OpenRC-ish rc: `vendor_payload/`,
  baked via `make_final_vendor.sh` (loop-mount + os.setxattr WITH trailing
  \x00 on security.selinux — debugfs ea_set loses the NUL and breaks labels!).
- SSH access: `adb forward tcp:22222 tcp:2222; ssh -i gm8_node_key -p22222 shell@127.0.0.1`

### 3.2 TWRP rescue ✅
`fastboot boot 3.6.2_twrp.img` → adb "recovery", uid0 shell. RAM-boot only;
flashing TWRP to boot slots works but unnecessary.

### 3.3 Previous fallback OS state (superseded by section 0)
boot_a/boot_b = pristine stock · vendor_a/b = stock · system_a = **Alpine SAR
image (historically appeared hung; now resolved)** · system_b = stock 9.0 image from QFIL folder ·
misc = zeros · devinfo = unlocked · userdata = ext4 with old partial Alpine
(harmless; p52).

To return to fully-stock Android: EDL-write original system_a back:
```
cd /path/to/edl            # https://github.com/bkerler/edl
python edl.py --loader "$LOADER" w system_a "$STOCK_ROM_DIR/system_a"
python edl.py --loader "$LOADER" reset
```
NOTE: that folder's system_a is Android 8.1 (device shipped 8.1→OTA 9);
system_b file in same folder is 9.0. Both verified bootable.

## 4. TOOLING MAP
- EDL client: [bkerler/edl](https://github.com/bkerler/edl) in a Python venv (`edl.py`)
- Programmer (correct SoC):
  `prog_emmc_firehose_8940_ddr.mbn` from the stock QFIL package (`$LOADER`; it is
  vendor firmware and is not redistributed here)
- udev rule exists for 05c6:9008 (mode 0666)
- fastboot/adb: system PATH
- pmbootstrap venv: any Python venv (recreate if lost:
  pip install git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git)
  cfg: `~/.config/pmbootstrap_v3.cfg` (device=general-mobile-gm8)
- pmaports clone w/ our aports:
  `~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/
     device-general-mobile-gm8/  +  linux-postmarketos-general-mobile-gm8/`
- pmbootstrap needs passwordless sudo on the build host
- Kernel sources cloned under `pmos/kernel/`:
  gm8-kernel (downstream 3.18.140 GPL, defconfig msm8937-perf),
  msm89x7-mainline (7.x mainline fork, msm8940.dtsi + santoni ref board)
- Stock boot images (restore points): ROM folder boot_a/boot_b (verified via
  readback md5), plus your own dump of `boot_b`
- SSH keypair: `gm8_node_key[.pub]`

## 5. TRAPS WE FELL INTO (do not repeat)
5.1 **Vibration marker test INVALID as run:** our buzz wrote
    `/sys/class/leds/vibrator/activate` (mainline LED API). This downstream
    kernel almost certainly exposes the OLD timed-output API
    (`/sys/class/timed_output/vibrator/enable`) or qpnp haptics path — so
    "no buzz" does NOT prove /init didn't run! Re-test with both APIs.
5.2 AIK-Linux repack zeroes LK-required boot header fields → silent no-boot.
    Use `boot_splice.py` (byte-splice preserving full 660-byte header).
5.3 mke2fs 1.47 defaults (orphan_file, metadata_csum_seed, metadata_csum,
    64bit, extra_isize, ext_attr) — 3.18 may refuse mount. Final working-
    candidate feature set: `-O has_journal,resize_inode,dir_index,filetype,
    extent,sparse_super,large_file,huge_file,dir_nlink,flex_bg` + `-b4096 -I256`.
5.4 aarch64-linux-musl binutils wrappers segfault (nm/ar) → empty
    vdso-offsets.h, corrupt archives. Use pmbootstrap chroot toolchain
    (LLVM=1 builds work) or GNU binutils.
5.5 `adb reboot bootloader` hangs stock 8.1; `adb reboot edl` works.
5.6 Slot roulette: always `fastboot getvar current-slot` or flash BOTH slots.
5.7 BCB `bootonce-bootloader` sticks → permanent fastboot; zero `misc`.
5.8 Don't mix the mislabelled "lineage-18.1" zip (actually Omni 9 eng) with
    stock vendor/firmware.
5.9 debugfs ea_set writes selinux xattr WITHOUT trailing NUL → broken label;
    prefer loop-mount + python os.setxattr(b"...s0\x00").

## 6. LEADING THEORIES FOR §1 (ranked)
T1. Exec of `/init` fails (ENOENT/ENOEXEC) → panic-hang. Verify via static-C
    /init experiment (§1.1) or UART.
T2. Root mount fails (residual fs feature or ro+fsck weirdness) → same hang.
    Verify: mkfs with ONLY `-O extents` style minimal (done once — was it
    tested? NO: the minimal-feature rebuild was flashed and result unknown —
    user reported silence again, but vibration invalidity means we can't tell
    whether userspace ran. RE-TEST WITH FIXED BUZZ API.)
T3. Kernel never reaches mount (earlier hang) — unlikely: same kernel boots
    Android normally right before each experiment (warm).
T4. LK appends args AFTER ours that break Alpine (e.g., `init=/init` fine,
    but also possibly `androidboot.selinux=enforcing` irrelevant w/o policy).

## 7. NEXT STEPS
The authoritative checklist is now
[`pmos/notes/REMAINING_WORK.md`](pmos/notes/REMAINING_WORK.md).

1. If the access point changes, regenerate the protected configuration at
   `/persist/gm8-wpa_supplicant.conf`; never commit credentials.  The Wi-Fi
   address is DHCP and may differ from the tested the address seen during testing.
2. Formalize the working downstream-kernel Wi-Fi setup in the pmbootstrap
   device package if this image stops being a one-off SAR build.
3. USB Ethernet is now operational. The authoritative investigation,
   reproducible patch sequence, tested hashes, rollback image, and remaining
   cleanup are in
   [`pmos/notes/USB_ETHERNET.md`](pmos/notes/USB_ETHERNET.md).

## 8. DEVICE STATE AT HANDOFF (exact)
- boot_a=custom SR9700-enabled kernel · boot_b=stock ·
  system_a=working Alpine-SAR · system_b=stock-9.0-img ·
  vendor_a/b=stock · userdata=old partial alpine ext4 (p52) ·
  devinfo=unlocked · board last verified booted as RNDIS `18d1:d002`, pinging
  at `172.16.42.1`, with working root SSH, read-write rootfs, WCNSS online,
  automatic Wi-Fi association, DHCP, direct Wi-Fi SSH/internet/NTP, working
  `apk update`, and working `0fe6:9702` Ethernet at 10 Mbps half-duplex.
  Ethernet DHCP routes are preferred over Wi-Fi, which remains the fallback.
  Temporary host RNDIS NAT rules were removed.
