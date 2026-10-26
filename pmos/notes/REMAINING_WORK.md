# GM8 port — remaining work

Last updated: 2026-08-26

## Current completion boundary

The headless Alpine node is operational on real hardware.  Normal boot,
OpenRC, read-write rootfs, RNDIS recovery SSH, Qualcomm WCNSS/Pronto Wi-Fi,
automatic WPA association, DHCP, direct Wi-Fi SSH, internet, NTP, and APK were
all verified after reboot.

This is not yet a clean, maintainable, upstreamable postmarketOS port.  The
working system uses the stock downstream Android kernel and a custom SAR image
builder.

## Required for a reproducible release

- [x] Rebuild the SAR image from the current builder.  The rebuilt image was
  flashed to `system_a` and verified on real hardware.
- [x] Boot the rebuilt image and repeat the acceptance test: RNDIS SSH,
  WCNSS/Pronto, automatic Wi-Fi association, DHCP, direct Wi-Fi SSH,
  internet, NTP, `apk update`, read-write rootfs, and reboot persistence.
- [x] Remove machine-specific absolute paths from
  `make_gm8_system_sar.sh`; source/output paths are now arguments or derived
  from the script directory.  The builder stages files and uses `mke2fs -d`,
  so loop-device mounts are not required.
- [x] Add a checked-in build script for the static AArch64 helper binaries.
  The exact-kernel `pronto_wlan.ko` remains an external stock-vendor input.
- [x] Run `build_gm8_root_tar.sh` and verify that a fresh root archive removes
  the inherited APK post-install errors.
- [x] Add a host-side USB networking helper to restore the RNDIS IPv4 address
  after reboot.
- [x] Add a single documented build-and-flash recipe with hashes and recovery
  instructions. See the device README.

## OS maintenance

- [ ] Move away from Alpine 3.19, which is end-of-life, to a maintained Alpine
  or postmarketOS release.
- [ ] Revalidate the stock 3.18.120 kernel against the newer userspace,
  especially OpenRC, networking, TLS, and module-loading behavior.
- [ ] Keep the RTC floor service for pre-network TLS and verify NTP correction
  on every supported image.

## Formal postmarketOS integration

- [ ] Archive or replace the current pmaports mainline kernel package.  It
  builds but does not boot because LK supplies an incompatible downstream DTB.
- [ ] Create a downstream-kernel device/kernel package matching the proven
  stock `3.18.120-perf-g5794ae0` boot path, or produce a documented source
  build that is binary-compatible with it.
- [ ] Package the WCNSS bring-up sequence, modem/persist mounts, calibration
  links, firmware-class path, and OpenRC services as device-package content.
- [ ] Decide how the exact Pronto module is distributed.  The current working
  module is a stock-vendor binary; check licensing/redistribution constraints
  or rebuild it from matching source.
- [ ] Treat modem firmware and device calibration as extracted/proprietary
  assets rather than committing user/device data.
- [ ] Make `pmbootstrap build`, `pmbootstrap install`, and the documented flash
  method reproduce the tested system without the custom one-off workflow.
- [ ] Update `PORT_PLAN.md`, the device `APKBUILD`, kernel `APKBUILD`,
  `deviceinfo`, checksums, maintainers, and the working hardware matrix before
  proposing anything upstream.

## Optional hardware scope

These are not required for the current headless-node goal, but remain untested
or unsupported as a general phone port:

- [ ] Bluetooth
- [ ] Audio input/output
- [ ] Cellular modem, SIM, calls, SMS, and mobile data
- [ ] Suspend/resume and wake sources
- [ ] GPU acceleration
- [ ] Display, backlight, touchscreen, and buttons as UI inputs
- [ ] Thermal monitoring/throttling and long-duration stability
- [ ] Charging/power behavior with a battery; the current board has no battery

## Definition of done

The headless-node work can be considered complete when the final rebuilt image
passes the reboot acceptance test and its build is reproducible on a clean
host.  A postmarketOS port is complete only when the pmaports packages—not the
custom SAR builder—produce the working image and the supported hardware list
is accurately documented.
