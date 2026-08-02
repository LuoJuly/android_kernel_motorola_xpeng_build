# kernel_motorola_xpeng_build

Build scripts for Motorola **xpeng** (Moto G200 5G / edge S30) kernel + WLAN, based on **MMI-S3RXC32.33-8-29**.

Kernel sources live in a separate repo:

- https://github.com/LuoJuly/android_kernel_motorola_xpeng  
  branch `kernel-msm-MMI-S3RXC32.33-8-29` (ReSukiSU)

## Layout

| Path | Role |
|------|------|
| `build-kernel.sh` | Build `Image` / modules |
| `build-wlan.sh` | Build `wlan.ko` for qca6490 / qca6750 / qca6390 |
| `build-all.sh` | Kernel + WLAN + install stripped kos |
| `setup.sh` | Fetch/link kernel, clang, gcc, Lineage host tools, WLAN trees |
| `out/wlan-modules/` | Optional prebuilt stripped WLAN modules |

Large local build trees (`out/target`, clang/gcc checkouts, WLAN `.wlan` objects) are **not** in git.

## One-time setup

Needs a Lineage (or AOSP) tree that still has:

- `prebuilts/build-tools`
- `prebuilts/misc` (`dtc`, `ufdt_apply_overlay`)
- `prebuilts/gcc/.../aarch64-linux-android-4.9` (or let `setup.sh` symlink it)

```bash
export LINEAGE_ROOT=~/android/lineage
./setup.sh
```

## Build

```bash
./build-all.sh
# or step by step:
./build-kernel.sh
./build-wlan.sh
```

Outputs:

- `out/target/product/generic/obj/kernel/msm-5.4/arch/arm64/boot/Image`
- `out/wlan-modules/wlan-*.ko`

## Notes

- On xpeng, `fastboot flash boot` may hit **Preflash validation failed**; flash `boot` via TWRP/`dd` instead.
- Disable AVB as needed with a flags-cleared `vbmeta` image.
