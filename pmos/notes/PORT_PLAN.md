# pmOS port plan — GM8_sprout (MSM8940)

## Where we are
- pmbootstrap 3.11.1 (venv a Python venv — RECREATE if /tmp wiped:
  `python3 -m venv venv && pip install git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git`)
- Config: `~/.config/pmbootstrap_v3.cfg` → device `general-mobile-gm8`,
  aports at `~/.local/var/pmbootstrap/cache_git/pmaports` (our device+kernel
  aports already added under device/testing/)
- Kernel sources:
  - Mainline fork clone: `pmos/kernel/msm89x7-mainline` (v7.1.3, has
    msm8940.dtsi + santoni reference board) — **our gm8 dts committed as
    pmos/device/gm8-dts.patch**
  - Downstream GPL: `GM-8-OpenSource/kernel_GM_GM8-3.18.140`
    (defconfig: msm8937-perf) + `GM-AndroidOne-Archive/kernel_GM_GM8_sprout`
  - TWRP device tree: `pmos/twrp-tree`

## MAINLINE ROUTE — POSTMORTEM (blocked, keep archived)
Built fine (clang in chroot), DT compiled, but device bootloops instantly.
Root cause hypothesis (high confidence): **LK passes its own downstream
MSM8940-MTP DTB to the kernel (x0); mainline arm64 trusts bootloader DTB and
never uses our appended one** → kernel wakes with 2015-vintage downstream
bindings → early panic before UART/USB. TWRP works because it's a downstream
kernel expecting exactly that DTB.
Unblock options (future): patch LK impossible (fuse-verified); make mainline
tolerate downstream DTB (huge); or find LK cmdline/config to disable DTB pass.
Artifacts kept: `pmos/device/gm8-dts.patch`, smoke images.

## ACTIVE PLAN: DOWNSTREAM KERNEL + ALPINE/pmOS ROOTFS
Classic pmOS downstream pattern; kernel is proven on this exact board.

### Steps
1. [ ] Toolchain: Arm legacy aarch64 GCC 8.3 (developer.arm.com) OR try
   pmbootstrap chroot gcc first; 3.18 + modern gcc needs known patches.
2. [ ] Build 3.18.140 w/ msm8937-perf_defconfig + fragment:
   - CONFIG_DEVTMPFS=y SYSVIPC=y IPV6=y CONFIGFS_FS=y
   - USB_CONFIGFS=y USB_F_RNDIS=y USB_F_FS=y FFS=y (gadget for ssh/net)
   - CONFIG_PSTORE_RAM=y (crash logs)
   - BUILD_ARM64_APPENDED_DTB_IMAGE=y (already in defconfig)
   - wcn36xx (+MAC80211 stack) for WiFi later
3. [ ] mkbootimg with PROVEN params:
   base=0x80000000 pagesize=2048 koff=0x8000 roff=0x1000000 toff=0x100
   Test via `fastboot boot` ONLY (no flashing!).
4. [ ] Initramfs v2 (reuse an initramfs work dir pattern — busybox +
   dropbear + configfs RNDIS @172.16.42.1). NOTE the bug we hit: busybox
   must live at /bin/busybox; include dropbear INSIDE; test init syntax!
5. [ ] Milestone A: RNDIS enumerates (1d6b:0104) + ssh works from RAM-boot.
6. [ ] pmbootstrap install --no-fde etc → rootfs image → flash userdata
   (EDL or fastboot), boot.img → both slots.
7. [ ] WiFi: enable &pronto/wifi node equivalents downstream are automatic;
      ship firmware from device modem partition (/vendor/firmware_mnt,
      wcnss.* files) into rootfs /lib/firmware.
8. [ ] Autostart sshd via pmOS OpenRC (default sshd service) — done deal.

### Gotchas learned (apply!)
- flash BOTH slots or check getvar current-slot
- misc BCB can wedge boot → zero it
- slot retries decay headless → set_active resets
- cold-plug no-battery = charge mode (f000): press POWER to continue
- never use AIK repack for this board's boot.img (zeroes needed header fields)

### Sharing checklist (when it works)
- device aports diff vs upstream pmaports
- kernel config file
- this notes dir + README recovery cookbook
