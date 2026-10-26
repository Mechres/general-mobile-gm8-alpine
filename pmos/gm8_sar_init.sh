#!/bin/sh

# PID 1 diagnostic shim for the stock GM8 kernel.  Keep this BusyBox-ash
# compatible: it runs before OpenRC and before any writable filesystems exist.

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || \
	mount -t tmpfs -o mode=0755 tmpfs /dev 2>/dev/null || true

# Leave an unambiguous, persistent trace that this script executed.  misc is a
# 1 MiB all-zero diagnostic partition in the current test setup; its final
# sector is outside Android's bootloader-message/wipe-package regions.  The
# marker can be read back over EDL even when the board later hangs silently.
mark_init_ran()
{
	# GPT readback proves misc is partition 30 on this exact board/image.
	dev=/dev/mmcblk0p30
	[ -b "$dev" ] || mknod "$dev" b 179 30 2>/dev/null || return 1
	printf 'GM8_INIT_RAN_v1\n' | \
		dd of="$dev" bs=512 seek=2047 conv=notrunc 2>/dev/null || return 1
	sync
}

mark_init_ran

vibrator_node()
{
	for node in \
		/sys/class/timed_output/vibrator/enable \
		/sys/class/leds/vibrator/activate \
		/sys/class/leds/vibrator/brightness
	do
		[ -w "$node" ] && { echo "$node"; return 0; }
	done
	return 1
}

buzz()
{
	node="$(vibrator_node)" || return 1
	case "$node" in
		*/timed_output/*/enable)
			# Android timed-output ABI: value is duration in milliseconds.
			echo 300 > "$node"
			;;
		*/activate)
			echo 300 > "$node"
			;;
		*/brightness)
			echo 255 > "$node"
			sleep 0.3
			echo 0 > "$node"
			;;
	esac
}

# The haptics driver can appear after /sys is mounted.  Wait up to five
# seconds, then emit three unmistakable pulses to prove that this script ran.
i=0
while [ "$i" -lt 50 ]; do
	if vibrator_node >/dev/null; then
		buzz
		sleep 0.5
		buzz
		sleep 0.5
		buzz
		break
	fi
	i=$((i + 1))
	sleep 0.1
done

# Keep Qualcomm's watchdog alive if the downstream driver exposed it.
for watchdog in /dev/watchdog /dev/watchdog0; do
	[ -c "$watchdog" ] && echo V > "$watchdog" 2>/dev/null
done

exec /sbin/init
