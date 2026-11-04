#!/bin/sh
set -eu

# The GM8 pins its host-side RNDIS MAC, so one NetworkManager profile matched
# on that address configures the link on any USB port or interface name, and
# survives reboots of either side.
CON=${GM8_CONNECTION:-gm8-usb}
MAC=${GM8_HOST_MAC:-02:67:38:00:00:02}
HOST_ADDR=${1:-172.16.43.2/24}

command -v nmcli >/dev/null 2>&1 || {
    echo "Missing nmcli" >&2
    exit 1
}

if nmcli -t -f NAME connection show | grep -qx "$CON"; then
    sudo nmcli connection modify "$CON" ethernet.mac-address "$MAC" \
        ipv4.method manual ipv4.addresses "$HOST_ADDR" ipv4.never-default yes \
        ipv6.method disabled connection.autoconnect yes
else
    sudo nmcli connection add type ethernet con-name "$CON" ifname '*' \
        ethernet.mac-address "$MAC" \
        ipv4.method manual ipv4.addresses "$HOST_ADDR" ipv4.never-default yes \
        ipv6.method disabled connection.autoconnect yes
fi
sudo nmcli connection up "$CON" >/dev/null 2>&1 || \
    echo "Profile $CON saved; it activates when the GM8 enumerates"

echo "GM8 USB network profile ready: $CON ($MAC) -> $HOST_ADDR"
