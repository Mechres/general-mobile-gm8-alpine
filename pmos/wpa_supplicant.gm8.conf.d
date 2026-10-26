# GM8 has both p2p0 and wlan0; never rely on first-interface discovery.
wpa_supplicant_args=""
wpa_supplicant_if="wlan0"
wpa_supplicant_dbus=no
rc_need="gm8-wifi-hw"
