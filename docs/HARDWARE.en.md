# Hardware & Tuners

## Quick Navigation

- [Project Overview](README.en.md)
- [Quickstart](QUICKSTART.en.md)
- [Testing Guide](TESTING.en.md)
- [Packaging Guide](PACKAGING.en.md)
- [Hardware Notes](HARDWARE.en.md) *(this page)*
- Prefer German? See [HARDWARE.de.md](HARDWARE.de.md)

## Device preparation

1. Add your user to the `video`, `input`, `dvb`, and `plugdev` groups:
   ```bash
   sudo usermod -a -G video,input,dvb,plugdev $USER
   ```
2. Copy firmware blobs to `/lib/firmware` according to vendor guidance.
3. Reboot or re-login so the new group memberships take effect.

## Device detection

`scripts/detect_devs.sh` enumerates DVB, V4L2, and input devices.

```bash
make test-hw
```

Output is bilingual and, with `--verbose`, includes udev properties.

## Known-good combinations (examples)

- USB DVB-C tuners based on the RTL2832U chipset with recent kernels.
- PCIe dual tuners (CX23885 family) on kernels ≥ 5.10.

> Note: The list intentionally stays generic. Always confirm vendor/kernel support matrices.

## Out-of-tree tuner drivers (DVB)

Not every tuner is covered by the in-kernel driver. If `/dev/dvb` stays empty
although the tuner is attached, the driver may have to be built out of tree
(media_build / linux-media).

- Helper repo: <https://github.com/dbt1/linux-media> builds the modules per
  tuner profile (e.g. TBS5580 USB) and keeps them in `out/` instead of
  installing to `/lib/modules`.
  **A developer's personal repository — not part of Tuxbox and not supported.**
  It is mentioned only as one workable route; any other media_build setup works
  just as well.
- Prerequisite: matching kernel headers — `sudo apt install linux-headers-amd64`
  as a meta package so they follow kernel updates.
- **Maintenance:** such modules are tied to the running kernel's vermagic. After
  every kernel update they must be **rebuilt**, otherwise `/dev/dvb` disappears
  and Neutrino starts without a tuner — this is not a defect of Neutrino or this
  build system.

> Note: `neutrino-generic-build` does not build these drivers itself. Driver
> provisioning is host- and kernel-specific and lives in the linux-media helper,
> not in this repo.

## Running hardware smoke tests

1. Launch Neutrino with `make run`. Run it as your normal user — never
   `sudo make`, which would leave root-owned build artifacts behind. If the
   tuner is not reachable, add yourself to the `video` group
   (`sudo usermod -aG video $USER`, then log in again) rather than elevating
   the build.
2. Ensure `/dev/dvb/adapter*` exists (otherwise double-check firmware).
3. Execute manual smoke tests, e.g. channel scan via the Neutrino menu.

## Troubleshooting

- **Missing devices**: Inspect `dmesg` for kernel module/firmware issues.
- **Devices gone after a kernel update**: rebuild out-of-tree modules against the new kernel (see the "Out-of-tree tuner drivers (DVB)" section).
- **Permission denied**: Verify group memberships with `id $USER`.
- **No video/audio**: Inspect the `libstb-hal` build and analyze logs stored under `logs/`.
