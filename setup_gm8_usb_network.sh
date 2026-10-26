#!/bin/sh
set -eu

IFACE=${1:-enp15s0f3u1}
HOST_ADDR=${2:-172.16.42.2/24}

command -v nmcli >/dev/null 2>&1 || {
    echo "Missing nmcli" >&2
    exit 1
}
command -v ip >/dev/null 2>&1 || {
    echo "Missing ip" >&2
    exit 1
}

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "USB network interface not found: $IFACE" >&2
    exit 1
fi

sudo nmcli device set "$IFACE" managed no
sudo ip link set "$IFACE" up
sudo ip addr replace "$HOST_ADDR" dev "$IFACE"

echo "GM8 USB network ready: $IFACE -> $HOST_ADDR"
ip -br addr show dev "$IFACE"
