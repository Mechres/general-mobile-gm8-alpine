# GM8 build inputs

The working Alpine SAR image is assembled by
[`make_gm8_system_sar.sh`](../make_gm8_system_sar.sh).

## Rebuildable inputs

Build the four static AArch64 helper binaries from their checked-in C sources:

```sh
./pmos/build_gm8_helpers.sh
```

The default compiler is `aarch64-linux-musl-gcc`; override it with `CC=...` if
needed. The generated binaries are intentionally ignored by Git.

## External inputs

The image builder still requires two host/device-specific inputs that are not
stored in this repository:

1. `gm8_sar_root.tar` — the Alpine rootfs archive produced by the pmbootstrap
   environment. Rebuild it with:

   ```sh
   ./pmos/build_gm8_root_tar.sh /path/to/gm8_sar_root.tar
   ```

   The script uses a separate `/gm8root-repro` chroot path and does not modify
   the older `/gm8root` tree.
2. `pmos/pronto_wlan.ko` — the exact-kernel Qualcomm Pronto module extracted
   from the stock vendor image. It must match
   `3.18.120-perf-g5794ae0` and is not rebuilt by this project.

The tested module SHA-256 is:

```text
792b4afe99710bba26137106da97ff0bff03057f89e344fd5a0d83ad10faf052  pmos/pronto_wlan.ko
```

The protected Wi-Fi configuration on the phone is deliberately not an image
input. It remains on the `persist` partition, and no SSID or passphrase should
be added to this repository.
