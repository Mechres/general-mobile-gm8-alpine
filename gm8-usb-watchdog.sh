#!/bin/sh
# Host-side watchdog for the GM8's USB network link (rndis_host, 172.16.43.1).
# The GM8's downstream 3.18 RNDIS gadget sometimes stops answering, idle or
# under load, while USB stays enumerated and the phone keeps running; a bus
# reset of the device brings it back within seconds (found 2026-11-10).
# After MISSES consecutive failed pings, reset the device if it is attached,
# then wait HOLDOFF seconds before checking again.
IP=${GM8_IP:-172.16.43.1}
DEV=${GM8_USB_ID:-18d1:d002}
MISSES=${GM8_MISSES:-5}
HOLDOFF=${GM8_HOLDOFF:-30}
miss=0
while :; do
  if ping -c1 -W1 "$IP" >/dev/null 2>&1; then
    miss=0
  else
    miss=$((miss + 1))
  fi
  if [ "$miss" -ge "$MISSES" ]; then
    if lsusb -d "$DEV" >/dev/null 2>&1; then
      echo "gm8 $IP silent for $miss s; resetting USB $DEV"
      usbreset "$DEV" >/dev/null 2>&1
      sleep 5
      if ping -c1 -W2 "$IP" >/dev/null 2>&1; then echo "gm8 recovered"; else echo "gm8 still silent after reset"; fi
      sleep "$HOLDOFF"
    fi
    # Not attached: unplugged or rebooting, nothing to reset.
    miss=0
  fi
  sleep 1
done
