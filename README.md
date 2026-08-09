# android_kernel_motorola_xpeng_build

Build scripts for Motorola **xpeng** (Moto G200 5G / Edge S30) kernel + WLAN, plus weekly **ReSukiSU** boot / AnyKernel3 / WiFi KSU GitHub Actions.

## Active CI branch: `5.4.302-s3rxc32.33-8-25-ReSukiSU`

| Item | Value |
|------|-------|
| Kernel source | [`android_kernel_motorola_xpeng` @ `5.4.302-s3rxc32.33-8-25`](https://github.com/LuoJuly/android_kernel_motorola_xpeng/tree/5.4.302-s3rxc32.33-8-25) |
| Kernel version label | **5.4.302** |
| ROM id | `S3RXC32.33-8-25` |
| Legacy scripts branch | `S3RXC32.33-8-29-ReSukiSU` (8-29 kernel, no live WiFi pack) |

Kernel sources are **not** in this repo. They are fetched by git.

## Layout

| Path | Role |
|------|------|
| `build-kernel.sh` / `build-wlan.sh` / `build-all.sh` | Local MMI-style builds |
| `setup.sh` | Fetch/link kernel, clang, gcc, Lineage host tools, WLAN trees |
| `scripts/ci/build_resukisu_boot.sh` | Clone kernel → ReSukiSU → Image → **WiFi kos** → KSU zip → boot → AnyKernel3 |
| `scripts/ci/build_wlan_modules.sh` | Build vermagic-matched `qca_cld3_*.ko` against current `O=` |
| `scripts/ci/pack_wlan_ksu_module.sh` | Pack Magisk/KernelSU WiFi zip |
| `scripts/ci/pack_anykernel3.sh` | Pack AnyKernel3 (**Image + bundled WiFi KSU zip**) |
| `scripts/ci/wlan-ksu-module-template/` | Magisk module scripts (`service.sh` late-insmod) |
| `.github/workflows/` | Weekly Actions for Edge S30 + G200 |

## Pipeline (each variant)

1. Clone/update kernel `5.4.302-s3rxc32.33-8-25` (+ ReSukiSU submodule)
2. Build `Image` (NFC off for Edge S30, on for G200)
3. Build WiFi modules against that Image (`qca_cld3_{wlan,qca6750,qca6390}.ko`)
4. Pack standalone `wlan_crc_match_5.4.302-ksu-g*.zip`
5. Repack `boot_ksu.img`
6. Pack `AnyKernel3-*-5.4.302-*.zip` containing **kernel + WiFi KSU zip**
7. Publish Release assets

## ReSukiSU weekly CI

| Workflow | Device | NFC | Schedule (UTC) |
|----------|--------|-----|----------------|
| `build-resukisu-edge-s30.yml` | Moto Edge S30 (XT2175-2) | off | Sun 00:00 |
| `build-resukisu-g200.yml` | Moto G200 5G (XT2175-1) | on | Sun 02:00 |

### Local build

```bash
export XPENG_BUILD_ROOT=$PWD
export KERNEL_SRC=~/android/mmi-8-25-upstreaming   # optional local tree on 5.4.302 branch

./scripts/ci/run_local_both.sh

# or one variant
VARIANT=edge-s30 ./scripts/ci/build_resukisu_boot.sh
VARIANT=g200 ./scripts/ci/build_resukisu_boot.sh
```

Artifacts: `.ci-work/<variant>/release/`

- `boot_ksu.img` / `Image`
- `wlan_crc_match_5.4.302-ksu-g*.zip`
- `AnyKernel3-*-5.4.302-*.zip` (includes `wlan_crc_match_ksu.zip`)

## HOW TO USE

```
fastboot reboot fastboot
fastboot flash boot boot_ksu.img
# If needed:
fastboot -w
```

AnyKernel3: flash in recovery / Kernel Flasher (installs kernel; best-effort installs WiFi module, also copies zip to `/sdcard/Download/`).

Standalone WiFi zip: install via KernelSU Manager after first boot, then reboot.
