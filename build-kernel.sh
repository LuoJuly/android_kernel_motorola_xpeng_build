#!/usr/bin/env bash
set -euo pipefail
my_top_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$my_top_dir"

mkdir -p "$my_top_dir/out/target/product/generic/obj/kernel/msm-5.4"
kernel_out_dir=$my_top_dir/out/target/product/generic/obj/kernel/msm-5.4

clang=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/clang
ld_lld=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/ld.lld
llvm_ar=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/llvm-ar
llvm_nm=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/llvm-nm
make=$my_top_dir/prebuilts/build-tools/linux-x86/bin/make
aarch64_linux_android_=$my_top_dir/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-

# dtc workaround from Motorola forum / readme discussion
local_dtc=$my_top_dir/prebuilts/misc/linux-x86/dtc/dtc
local_ufdt=$my_top_dir/prebuilts/misc/linux-x86/libufdt/ufdt_apply_overlay

# host ar/ld: use llvm tools (AOSP host gcc bins pruned upstream)
x86_64_linux_ar=$llvm_ar
x86_64_linux_ld=$ld_lld

export PATH="$(dirname "$clang"):$PATH"
export TARGET_BUILD_VARIANT=user
export TARGET_PRODUCT=xpeng_retcn

for t in "$clang" "$ld_lld" "$llvm_ar" "$llvm_nm" "$make" "${aarch64_linux_android_}gcc" "$local_dtc" "$local_ufdt"; do
  if [ ! -x "$t" ]; then
    echo "MISSING: $t" >&2
    exit 1
  fi
done

echo "==> envsetup lahaina"
cd "$my_top_dir/kernel/msm-5.4/scripts/gki"
# envsetup uses `ls ... 2>/dev/null` which returns non-zero when absent; don't abort
set +e
# shellcheck disable=SC1091
source "$my_top_dir/kernel/msm-5.4/scripts/gki/envsetup.sh" lahaina
set -e
cd "$my_top_dir"

HOSTCFLAGS="-I$my_top_dir/kernel/msm-5.4/include/uapi -I/usr/include -I/usr/include/x86_64-linux-gnu -I$my_top_dir/kernel/msm-5.4/include -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
HOSTLDFLAGS="-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
COMMON_MAKE=(
  ARCH=arm64
  CROSS_COMPILE="$aarch64_linux_android_"
  REAL_CC="$clang"
  CLANG_TRIPLE=aarch64-linux-gnu-
  AR="$llvm_ar"
  LLVM_NM="$llvm_nm"
  LD="$ld_lld"
  NM="$llvm_nm"
  DTC_EXT="$local_dtc"
  DTC_OVERLAY_TEST_EXT="$local_ufdt"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y
  HOSTCC="$clang"
  HOSTAR="$x86_64_linux_ar"
  HOSTLD="$x86_64_linux_ld"
)

echo "==> generate_defconfig vendor/lahaina-qgki_defconfig"
MAKE_PATH= ARCH=arm64 \
  CROSS_COMPILE="$aarch64_linux_android_" \
  REAL_CC="$clang" CLANG_TRIPLE=aarch64-linux-gnu- \
  AR="$llvm_ar" LLVM_NM="$llvm_nm" LD="$ld_lld" NM="$llvm_nm" \
  KERN_OUT="$kernel_out_dir" \
  DTC_EXT="$local_dtc" DTC_OVERLAY_TEST_EXT="$local_ufdt" \
  CONFIG_BUILD_ARM64_DT_OVERLAY=y \
  HOSTCC="$clang" HOSTAR="$x86_64_linux_ar" HOSTLD="$x86_64_linux_ld" \
  TARGET_BUILD_VARIANT=user \
  kernel/msm-5.4/scripts/gki/generate_defconfig.sh vendor/lahaina-qgki_defconfig

echo "==> defconfig"
"$make" -j"$(nproc)" -C kernel/msm-5.4 O="$kernel_out_dir" \
  "${COMMON_MAKE[@]}" \
  HOSTCFLAGS="$HOSTCFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
  vendor/lahaina-qgki_defconfig

echo "==> headers_install"
"$make" -j"$(nproc)" -C kernel/msm-5.4 O="$kernel_out_dir" \
  "${COMMON_MAKE[@]}" \
  HOSTCFLAGS="$HOSTCFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
  headers_install

echo "==> build kernel"
"$make" -j"$(nproc)" -C kernel/msm-5.4 O="$kernel_out_dir" \
  "${COMMON_MAKE[@]}" \
  HOSTCFLAGS="$HOSTCFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS"

echo "==> modules_install"
"$make" -j"$(nproc)" -C kernel/msm-5.4 O="$kernel_out_dir" \
  "${COMMON_MAKE[@]}" \
  HOSTCFLAGS="$HOSTCFLAGS" HOSTLDFLAGS="$HOSTLDFLAGS" \
  INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$kernel_out_dir/staging" \
  modules_install

echo "==> DONE"
ls -lh "$kernel_out_dir/arch/arm64/boot/Image" "$kernel_out_dir/arch/arm64/boot/Image.gz" 2>/dev/null || true
ls -lh "$kernel_out_dir/arch/arm64/boot/dts/vendor/qcom/"*.dtb 2>/dev/null | head || true
find "$kernel_out_dir/staging" -name '*.ko' 2>/dev/null | wc -l
