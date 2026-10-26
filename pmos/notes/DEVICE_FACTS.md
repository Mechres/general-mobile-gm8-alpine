# GM8_sprout — pmOS port facts (verified 2026-08-24)

## Hardware
- SoC: Qualcomm MSM8940 (Snapdragon 435), 8x Cortex-A53, Adreno 505
- RAM: 3GB, eMMC 32GB (mmcblk0), NO battery (bench PSU 4.2V!)
- Arch: aarch64

## Boot image header (from stock boot_b, PROVEN)
- base=0x80000000 pagesize=2048 kernel_offset=0x8000
- ramdisk_offset=0x1000000 tags_offset=0x100
- cmdline: console=ttyHSL0,115200,n8 androidboot.console=ttyHSL0
  androidboot.hardware=qcom ... buildvariant=user veritykeyid=...
- dtb: appended inside zImage (unpackbootimg shows no -dtb file)

## Partition layout (A/B, active slot varies!)
boot_a/b 64MiB | system_a/b 3GiB | vendor_a/b 1GiB | userdata 22GiB
misc 1MiB (BCB @0 + slot metadata @2048!) | devinfo 1MiB (is_unlocked dword@0x10)

## Boot behavior quirks (HARD-WON)
- COLD power plug, no battery => CHARGE MODE (05c6:f000), skips Android.
  Short-press POWER button to proceed to normal boot.
- Warm reboots (fastboot reboot / adb reboot) => normal boot path.
- `fastboot continue` resumes boot from fastboot shell.
- LK writes/consumes BCB "bootonce-bootloader": if stuck, EVERY boot -> fastboot.
  Fix: zero `misc` via EDL.
- Slot retry counters decay when userspace never marks success =>
  both slots unbootable => fastboot-only. Fix: `fastboot set_active <s>`.
- devinfo unlocked (dword@0x10=1): boot signature verification SKIPPED.
  aboot string proof: "Device is unlocked! Skipping verification..."
- EDL works always: edl.py --loader prog_emmc_firehose_8940_ddr.mbn
  (bkerler/edl client)
- TWRP 3.6.2 RAM-boots reliably: `fastboot boot 3.6.2_twrp.img` => adb root shell
- Rescue images kept in project root (gm8s_D_root.img = stock boot w/ insecure adb)

## Working OS state (fallback)
- Stock 8.1 (system_a) + patched vendor (dropbear ready) => authorized adb,
  verifiedbootstate=orange, SELinux enforcing, /data persistent.
