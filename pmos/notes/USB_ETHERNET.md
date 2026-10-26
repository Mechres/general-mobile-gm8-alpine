# GM8 USB Ethernet: verified SR9700/0fe6:9702 support

## Verified state (2026-08-30)

USB Ethernet works persistently on GM8 slot A alongside Wi-Fi.

- Adapter: `0fe6:9702 USB 2.0 10/100M Ethernet Adaptor`
- Interface 0 is the virtual driver CD-ROM; interface 1 is Ethernet.
- Kernel: `3.18.120-perf-g5794ae0`
- Hardware MAC: (device specific)
- Tested Ethernet IPv4: a DHCP address on the LAN
- Tested Wi-Fi IPv4: a DHCP address on the LAN
- Ethernet route metric: `209`
- Wi-Fi route metric: `310`
- RX and TX worked with zero errors.

Ethernet is primary and Wi-Fi is the fallback. Alpine's udhcpc script uses a
base metric of 200 for wired interfaces and 300 for Wi-Fi, then adds the
interface index.

SR9700 is a USB 1.1 controller and current upstream Linux models it as fixed
10 Mbps half-duplex. The adapter's `10/100M` string is misleading: 100 Mbps is
impossible over its 12 Mbps USB link. Expect roughly 5--8 Mbps useful TCP
throughput. Wired jitter should usually be more consistent than Wi-Fi, though
half-duplex contention can increase latency under bidirectional load.

Do not disable or remove the adapter's 4-Mbit SPI NOR flash. It is unnecessary
for this device and risks damaging it.

## Kernel patch sequence

Apply to the October `ten-test` GM8 kernel source in this order:

1. `gm8-kernel-usb-ethernet.patch`
   - enables `CONFIG_USB_NET_SR9700=y`;
   - updates old ARM64 assembler section syntax.
2. `gm8-kernel-sr9700-id.patch`
   - binds `0fe6:9702`, interface 1 only.
3. `gm8-kernel-sr9700-9702-fixes.patch`
   - uses USB request `0x03` for single-register writes and `0x01` for
     multiple-register writes;
   - stops writing a nonexistent DM9601 multicast-filter block;
   - accepts all multicast when required;
   - uses a locally administered random MAC if PAR cannot initially be read.

The single-register command fix was decisive. Before it, `eth0` linked and
transmitted DHCP discovers, but RX stayed at zero because receive-control
writes did not take effect. Afterwards, the real MAC was readable, DHCP
completed, and RX/TX worked without errors.

## Build inputs

- Source: October `ten-test`, commit `24b850cb` (`october-kernel`)
- Source version: Linux 3.18.120
- Toolchain: official AOSP Android 9 AArch64 GCC 4.9 prebuilt
- Toolchain tag: `android-9.0.0_r61`
- Toolchain repository:
  `platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`

Newer host GCC builds completed but fell back to the installed stock kernel
after `fastboot boot`. GCC 4.9 produced the first custom kernel that actually
booted.

Build with `LOCALVERSION=` and preserve the exact release:

```text
3.18.120-perf-g5794ae0
```

Required config differences:

```text
CONFIG_LOCALVERSION="-perf-g5794ae0"
# CONFIG_LOCALVERSION_AUTO is not set
# CONFIG_MODULE_SIG_FORCE is not set
CONFIG_USB_NET_SR9700=y
```

Signature enforcement is disabled because the existing stock
`pronto_wlan.ko` is signed with a key unavailable to the rebuilt kernel. With
enforcement disabled and the exact release preserved, Wi-Fi loads and works,
while tainting the kernel. This is a security tradeoff. A future refinement
could import the stock public certificate.

The build expects Python 2 for `scripts/gcc-wrapper.py`; on a Python-3-only
host, update that small wrapper for Python 3. Modern host compilers may also
need `HOSTCFLAGS=-fcommon` for the old DTC code.

## Images and rollback

Installed and tested image:

```text
8a1eb45a5bf6e7ec7b7f38d9ac69cb851608b333fc7d795a4aa530666f6a3a57  gm8_sr9700_upstream_write_fix_ramboot.img
```

Original `boot_a` backup:

```text
98e2936ae2646624f2394cab2c47a249e2a3005ee8a1f144653d8f48d98f0a1f  gm8_boot_a_before_usb_ethernet.img
```

`replace_boot_kernel.py` replaces only the kernel payload while preserving
the original ramdisk and appended Qualcomm DTBs. Fastboot is sufficient for
installation and rollback; reserve EDL for recovery when fastboot is absent.

The phone has no battery, so testing at the distant Ethernet outlet required
flashing each viable candidate to `boot_a` before moving it.

## Network configuration

`pmos/interfaces`, also installed as `/etc/network/interfaces`, contains:

```text
auto eth0
iface eth0 inet dhcp

auto wlan0
iface wlan0 inet dhcp
```

Boot with the adapter attached so `auto eth0` is processed. Separate udhcpc
processes for Ethernet and Wi-Fi can coexist; Wi-Fi does not block Ethernet
DHCP.

## Diagnostic history

1. USB enumeration worked, but the stock kernel had no matching driver.
2. Adding only the interface ID bound the driver, but initialization stopped
   at `Error reading MAC address`.
3. Random-MAC fallback created `eth0`, but DHCP failed: TX increased while RX
   remained zero. Static-IP ping showed the same one-way behavior.
4. Comparing with upstream Linux exposed incorrect single-register USB writes
   and nonexistent multicast-filter programming in the old driver.
5. Backporting those fixes restored the real MAC, RX, DHCP, IPv4/IPv6, and
   preferred Ethernet routing.

The driver can still print a small burst of `kevent 4 may have been dropped`
during link startup. It did not affect the verified data path. A future
cleanup can backport upstream removal of the legacy MII/link-reset machinery.
