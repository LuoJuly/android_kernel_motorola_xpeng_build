# android_kernel_motorola_xpeng_build

Build scripts for Motorola **xpeng** (Moto G200 5G / Edge S30) kernel + WLAN, based on **MMI-S3RXC32.33-8-29**, plus **ReSukiSU** boot / AnyKernel3 GitHub Actions.

## Branch: `S3RXC32.33-8-29-ReSukiSU`

| Item | Value |
|------|-------|
| Kernel version | **5.4.210** |
| Kernel source branch | `android-12-release-S3RXC32.33-8-29` |
| CI schedule | **manual only** (`workflow_dispatch`) — weekly cron disabled |
| WiFi | **live-built** `qca_cld3_*.ko` packed into AnyKernel3 (`do.modules=1`) |

For the **5.4.302** pipeline, use branch [`5.4.302-s3rxc32.33-8-25-ReSukiSU`](https://github.com/LuoJuly/android_kernel_motorola_xpeng_build/tree/5.4.302-s3rxc32.33-8-25-ReSukiSU).

Kernel sources are **not** in this repo. They are fetched by git:

```bash
git clone --recursive https://github.com/LuoJuly/android_kernel_motorola_xpeng
# default branch: android-12-release-S3RXC32.33-8-29
```

## Layout

| Path | Role |
|------|------|
| `build-kernel.sh` | Build `Image` / modules (local MMI tree) |
| `build-wlan.sh` | Build `wlan.ko` for qca6490 / qca6750 / qca6390 |
| `build-all.sh` | Kernel + WLAN + install stripped kos |
| `setup.sh` | Fetch/link kernel, clang, gcc, Lineage host tools, WLAN trees |
| `prebuilt/boot_oem.img` | Stock boot (gitignored; downloaded from Release `z-assets-S3RXC32.33-8-29`) |
| `scripts/ci/build_resukisu_boot.sh` | Clone kernel → update ReSukiSU → Image → **WiFi kos** → boot → AnyKernel3 |
| `scripts/ci/build_wlan_modules.sh` | Build vermagic-matched `qca_cld3_*.ko` against current `O=` |
| `scripts/ci/pack_wlan_ksu_module.sh` | Optional Magisk/KernelSU WiFi zip (fastboot-only fallback) |
| `scripts/ci/pack_anykernel3.sh` | Pack latest [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) zip (**Image + vendor WiFi kos**, `do.modules=1`) |
| `scripts/ci/run_local_both.sh` | Local helper: Edge S30 (NFC off) + G200 (NFC on) |
| `.github/workflows/` | Manual Actions for both devices |

## ReSukiSU CI (manual)

| Workflow | Device | NFC | Trigger |
|----------|--------|-----|---------|
| `build-resukisu-edge-s30.yml` | Moto Edge S30 (XT2175-2) | off (default) | Actions → Run workflow |
| `build-resukisu-g200.yml` | Moto G200 5G (XT2175-1) | on (`CONFIG_NFC_QTI_I2C=m`) | Actions → Run workflow |

Each run:

1. Clones `android_kernel_motorola_xpeng` (`--recursive`)
2. Updates ReSukiSU submodule to latest `main` (optional input)
3. Builds kernel (NFC per variant)
4. Live-builds WiFi `qca_cld3_*.ko` against that Image (`WLAN_TAG=MMI-S3RXC32.33-8-29`)
5. Fetches `boot_oem.img` (local / `~/download` / Release asset), unpacks with magiskboot, replaces `kernel`, repacks
6. Packs AnyKernel3 (`do.modules=1`, `do.systemless=0`; vendor WiFi kos inside the zip)
7. Publishes Release assets: `boot_ksu.img`, `Image`, `AnyKernel3-*.zip`, optional `wlan_crc_match_*-ksu-*.zip`

OEM boot base image is stored as Release asset tag `z-assets-S3RXC32.33-8-29` (not in git) to keep pushes small and stay at the bottom of the Releases list.

Release notes include ReSukiSU Value, e.g. `v4.1.0-1332-g59c99fdf@ReSukiSU (35046/2)`.

### Local ReSukiSU build

```bash
# optional: use existing toolchains / kernel symlink from setup.sh
export XPENG_BUILD_ROOT=$PWD
export KERNEL_SRC=~/android/kernel-msm-MMI-S3RXC32.33-8-29   # optional

# both variants
./scripts/ci/run_local_both.sh

# or one variant
VARIANT=edge-s30 ./scripts/ci/build_resukisu_boot.sh
VARIANT=g200 ./scripts/ci/build_resukisu_boot.sh
```

Artifacts: `.ci-work/<variant>/release/`

- `boot_ksu.img` / `Image`
- `wlan_crc_match_5.4.210-ksu-g*.zip` (optional fastboot fallback)
- `AnyKernel3-*-ReSukiSU-*.zip` (kernel + `modules/vendor/lib/modules/qca_cld3_*.ko`)

## One-time setup (manual MMI build)

Needs a Lineage (or AOSP) tree that still has:

- `prebuilts/build-tools`
- `prebuilts/misc` (`dtc`, `ufdt_apply_overlay`)
- `prebuilts/gcc/.../aarch64-linux-android-4.9`

```bash
export LINEAGE_ROOT=~/android/lineage
./setup.sh
./build-all.sh
```

Outputs:

- `out/target/product/generic/obj/kernel/msm-5.4/arch/arm64/boot/Image`
- `out/wlan-modules/wlan-*.ko`

## HOW TO USE

```
# Press the volume down and power buttons to enter FASTBOOT mode, then enter the command to enter Fastboot mode.
# 按音量下和开机键进入 FASTBOOT 模式，输入命令，进入 Fastbootd
fastboot reboot fastboot

# Flash boot_ksu.img
# 刷写 boot_ksu.img
fastboot flash boot boot_ksu.img

# If the device fails to boot after flashing, you will need to format the Data.
# 如果刷写后无法开机，则需要格式化 Data
fastboot -w
```

AnyKernel3: flash in recovery / Kernel Flasher. It installs the kernel and pushes WiFi `.ko` to `/vendor/lib/modules/` (`do.modules=1`). **Do not** install the KernelSU WiFi module after flashing AnyKernel3.

Standalone WiFi zip: only needed if you flashed `boot_ksu.img` via fastboot (that path does not replace vendor kos).

Branch for CI scripts: `S3RXC32.33-8-29-ReSukiSU` (kernel **5.4.210**, manual Actions only)
