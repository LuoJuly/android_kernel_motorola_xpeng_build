# kernel_motorola_xpeng_build

Build scripts for Motorola **xpeng** (Moto G200 5G / Edge S30) kernel + WLAN, based on **MMI-S3RXC32.33-8-29**, plus weekly **ReSukiSU** boot / AnyKernel3 GitHub Actions.

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
| `prebuilt/boot_oem.img` | Stock boot (gitignored; downloaded from Release `assets-S3RXC32.33-8-29`) |
| `scripts/ci/build_resukisu_boot.sh` | Clone kernel → update ReSukiSU → build → repack boot → AnyKernel3 |
| `scripts/ci/pack_anykernel3.sh` | Pack latest [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) zip |
| `scripts/ci/run_local_both.sh` | Local helper: Edge S30 (NFC off) + G200 (NFC on) |
| `.github/workflows/` | Weekly Actions (Sunday UTC) for both devices |

## ReSukiSU weekly CI (two scripts / workflows)

| Workflow | Device | NFC | Schedule (UTC) |
|----------|--------|-----|----------------|
| `build-resukisu-edge-s30.yml` | Moto Edge S30 (XT2175-2) | off (default) | Sun 00:00 |
| `build-resukisu-g200.yml` | Moto G200 5G (XT2175-1) | on (`CONFIG_NFC_QTI_I2C=m`) | Sun 02:00 |

Each run:

1. Clones `android_kernel_motorola_xpeng` (`--recursive`)
2. Updates ReSukiSU submodule to latest `main`
3. Builds kernel (NFC per variant)
4. Fetches `boot_oem.img` (local / `~/download` / Release asset), unpacks with magiskboot, replaces `kernel`, repacks
5. Packs AnyKernel3 from latest upstream
6. Publishes Release assets: `boot_ksu.img`, `Image`, `AnyKernel3-*.zip`

OEM boot base image is stored as Release asset tag `assets-S3RXC32.33-8-29` (not in git) to keep pushes small.

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

Branch for CI scripts: `S3RXC32.33-8-29-ReSukiSU`
