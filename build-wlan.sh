#!/usr/bin/env bash
set -euo pipefail
my_top_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$my_top_dir"

kernel_out_dir=$my_top_dir/out/target/product/generic/obj/kernel/msm-5.4
WLAN_BLD_DIR=$my_top_dir/vendor/qcom/opensource/wlan
WLAN_ROOT=$WLAN_BLD_DIR/qcacld-3.0

clang=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/clang
ld_lld=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/ld.lld
llvm_ar=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/llvm-ar
llvm_nm=$my_top_dir/prebuilts/clang/host/linux-x86/clang-r383902b1/bin/llvm-nm
make=$my_top_dir/prebuilts/build-tools/linux-x86/bin/make
aarch64_linux_android_=$my_top_dir/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
local_dtc=$my_top_dir/prebuilts/misc/linux-x86/dtc/dtc
local_ufdt=$my_top_dir/prebuilts/misc/linux-x86/libufdt/ufdt_apply_overlay

export PATH="$my_top_dir/bin:$(dirname "$clang"):$PATH"
export ANDROID_BUILD_TOP=$my_top_dir

test -f "$kernel_out_dir/Makefile" || { echo "Kernel out missing; build kernel first"; exit 1; }
test -d "$WLAN_ROOT" || { echo "qcacld-3.0 missing"; exit 1; }

echo "==> setup per-chip build trees"
target_chip=(qca6750 qca6390 wlan)
cd "$WLAN_ROOT"
for chip in "${target_chip[@]}"; do
  mkdir -vp "$WLAN_ROOT/.$chip"
  ln -sfn "$WLAN_BLD_DIR/qca-wifi-host-cmn" "$WLAN_ROOT/.$chip/qca-wifi-host-cmn"
  # link all top-level nodes into .$chip
  while IFS= read -r -d '' node; do
    base=$(basename "$node")
    case "$base" in .|..|.*|*~) continue ;; esac
    ln -sfn "$WLAN_ROOT/$base" "$WLAN_ROOT/.$chip/$base"
  done < <(find "$WLAN_ROOT" -mindepth 1 -maxdepth 1 -print0)
done
cd "$my_top_dir"

COMMON=(
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
  HOSTAR="$llvm_ar"
  HOSTLD="$ld_lld"
  CONFIG_INPUT_EGISTEC_FPS_NAVI=y
  CONFIG_INPUT_EGISTEC_FPS_NAVI_HORIZON=y
  CONFIG_INPUT_EGISTEC_FPS_NAVI_VERTICAL=y
  CONFIG_NAV_DOUBLE_TAP=y
  CONFIG_INPUT_MISC_FPC1020_SAVE_TO_CLASS_DEVICE=y
  CONFIG_MMI_RELAY=y
  CONFIG_INPUT_FOCALTECH_0FLASH_MMI_IC_NAME=ft8719
  CONFIG_INPUT_TOUCHSCREEN_MMI=y
  CONFIG_INPUT_FOCALTECH_0FLASH_MMI_IC_NAME=ft3518u
  CONFIG_INPUT_FOCALTECH_MMI_IC_NAME=ft3519
  CONFIG_INPUT_GCORE_MMI_NOTIFY_TOUCH_STATE=y
  CONFIG_INPUT_HIMAX_V2_MMI_IC_NAME=hx83102
  CONFIG_INPUT_HIMAX_V2_MMI_IC_NAME=hx83112
  CONFIG_INPUT_HIMAX_V2_MMI_IC_NAME_D=hx83102d
  CONFIG_INPUT_ILI_0FLASH_MMI_NOTIFY_TOUCH_STATE=y
  CONFIG_INPUT_NOVA_0FLASH_MMI_NOTIFY_TOUCH_STATE=y
  CONFIG_TOUCH_PANEL_NOTIFICATIONS=y
  CONFIG_TS_KERNEL_USE_GKI=y
  CONFIG_SEC_NFC_PRODUCT_N5=y
  CONFIG_SEC_NFC_IF_I2C=y
  CONFIG_USE_MMI_CHARGER=y
  CONFIG_SGM4154X_CHARGER_NAME=
  CONFIG_SND_SOC_CS35L41_SPI=y
  WLAN_COMMON_ROOT=./qca-wifi-host-cmn
  WLAN_COMMON_INC=vendor/qcom/opensource/wlan/qca-wifi-host-cmn
  WLAN_FW_API=vendor/qcom/opensource/wlan/fw-api
  WLAN_PROFILE=default
  MODNAME=wlan
  BOARD_PLATFORM=lahaina
  CONFIG_QCA_CLD_WLAN=m
  ANDROID_BUILD_TOP="$my_top_dir"
)

build_chip() {
  local chip=$1 cnss_flag=$2
  local mdir="$WLAN_ROOT/.$chip"
  echo "==> build chip=$chip"
  "$make" -j"$(nproc)" -C "$kernel_out_dir" M="$mdir" \
    "${COMMON[@]}" \
    modules \
    WLAN_ROOT="vendor/qcom/opensource/wlan/qcacld-3.0/.$chip" \
    DYNAMIC_SINGLE_CHIP="$chip" \
    DEVNAME="$chip" \
    "$cnss_flag"
  echo "==> chip $chip done"
  find "$mdir" -name 'wlan.ko' -o -name '*.ko' | head -20
}

# Prefer absolute M=; paths in WLAN_* match ANDROID_BUILD_TOP-relative includes
build_chip wlan 'CONFIG_CNSS_QCA6490=y'
build_chip qca6750 'CONFIG_CNSS_QCA6750=y'
build_chip qca6390 'CONFIG_CNSS_QCA6390=y'

echo "==> WLAN DONE"
find "$WLAN_ROOT" -name 'wlan.ko' -ls
