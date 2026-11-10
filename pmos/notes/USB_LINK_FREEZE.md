# USB network link freeze (stock 3.18 kernel)

Found 2026-11-10 while using the GM8 as a distributed-inference worker that
receives multi-GB weight shards over the USB link.

## Symptom

The USB network link (RNDIS `18d1:d002`, `172.16.43.1`) stops passing
traffic while the phone keeps running:

- The host gets no replies, not even ARP (`ip neigh` shows `FAILED`). Its TX
  counters keep rising and RX stops.
- Under load the host logs
  `rndis_host ... NETDEV WATCHDOG: transmit queue 0 timed out`.
- USB stays enumerated: the host logs no disconnect, and uptime shows the
  phone did not reboot.
- The GM8's kernel logs nothing about it.
- It does not recover by itself. One freeze lasted from overnight until a
  power cycle about 14 hours later.

A USB bus reset from the host (`usbreset 18d1:d002`) brings the link back
within seconds. Plain TCP connections survive that reset. A longer outage, or
an application with its own timeouts, does not.

## What triggers it

Measured with `nc` from the host into the GM8:

| Test | Result |
|---|---|
| 1 GB, GM8 writes to `/dev/null` | no freeze, ~20 MB/s |
| 800 MB `dd` to eMMC on the GM8, no network load | no freeze (90 MB/s) |
| 1.5 GB, GM8 writes to eMMC | freezes about every 45–60 s |
| same, host rate-limited to 8 MB/s with `tc tbf` | still freezes |
| same, USB IRQ 176 (`msm_hsusb`) moved from CPU0 to CPU2 | one clean run, then two freezes |
| same, gadget switched from `rndis` to `ncm` | freezes after ~325 MB |

So it takes heavy USB receive and eMMC writes at the same time. The NCM
result puts the bug below the network function, in the downstream USB
controller driver (`msm_otg`/`msm_hsusb`) or in how it interacts with the
eMMC path.

Power was ruled out as far as the gauge can show it. The battery-terminal
supply (bench buck, no battery) stayed at 4.32–4.38 V through a freeze, but
it is sampled only about once a second. The host side was ruled out too: no
USB2 LPM on this device, autosuspend off, no quirks.

Freezes also happen when the phone is idle. One came about 6 minutes after
boot, before the getty fix below; whether the getty flood caused that is
unknown.

## Workarounds

- **Host watchdog.** `gm8-usb-watchdog.sh` and `gm8-usb-watchdog.service` (in
  the repo root) ping the GM8 once a second. After 5 missed replies the
  watchdog resets the USB device, then waits 30 s. Install it with:
  ```
  sudo install -m755 gm8-usb-watchdog.sh /usr/local/bin/gm8-usb-watchdog
  sudo install -m644 gm8-usb-watchdog.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now gm8-usb-watchdog
  ```
  Its resets show up in `journalctl -u gm8-usb-watchdog`.
- **Avoid bulk writes over USB.** Small transfers and network-only traffic
  are fine. For large files, pre-copy over a transport that rides out a
  reset, or over Wi-Fi (slow: <250 KB/s).
- **getty flood (fixed in `build_gm8_root_tar.sh`).** The stock kernel has no
  virtual terminals, so Alpine's tty1–6 gettys exited at once and init
  respawned them about 6×/s. That left syslog with only ~3 minutes of
  history. On an existing image, comment out the `tty[1-6]` lines in
  `/etc/inittab` and run `kill -HUP 1`.

## Switching the gadget function at runtime

How the NCM test was run, in case it helps another kernel:

```
A=/sys/class/android_usb/android0
echo 0 > $A/enable; echo ncm > $A/functions; echo 1 > $A/enable
ip link set ncm0 up; ip addr add 172.16.43.1/24 dev ncm0
```

The host then sees MAC `42:40:3a:13:24:1b`, not the RNDIS `02:67:38:00:00:02`.
Writing `f_ncm/ncm_ethaddr` did not change that, so the MAC-matched
NetworkManager profile from `setup_gm8_usb_network.sh` does not apply. Run a
revert timer on the phone while testing: a switch that fails leaves the GM8
unreachable until reboot.

## Not tried

- A different eMMC I/O scheduler or `nr_requests`, or a limit on dirty
  writeback (`vm.dirty_bytes`), to shape the write side.
- A mainline kernel (see `PORT_PLAN.md`), whose chipidea/dwc USB driver is
  unrelated to the downstream one.
