#!/usr/bin/env bash
# Fetch toolchains, WLAN sources, and wire the kernel tree for local builds.
set -euo pipefail

TOP="$(cd "$(dirname "$0")" && pwd)"
cd "$TOP"

KERNEL_URL="${KERNEL_URL:-git@github.com:LuoJuly/android_kernel_motorola_xpeng.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-kernel-msm-MMI-S3RXC32.33-8-29}"
WLAN_TAG="${WLAN_TAG:-MMI-S3RXC32.33-8-29}"
CLANG_URL="${CLANG_URL:-https://mirrors.bfsu.edu.cn/git/AOSP/platform/prebuilts/clang/host/linux-x86}"
# Prefer a local Lineage tree if present; otherwise clone minimal host tools later.
LINEAGE_ROOT="${LINEAGE_ROOT:-$HOME/android/lineage}"

mkdir -p bin kernel prebuilts/clang/host prebuilts/gcc/linux-x86/aarch64 vendor/qcom/opensource/wlan
ln -sfn "$(command -v python3)" bin/python

echo "==> kernel ($KERNEL_BRANCH)"
if [ -e kernel/msm-5.4 ] && [ ! -L kernel/msm-5.4 ]; then
  echo "kernel/msm-5.4 exists and is not a symlink; leave as-is"
elif [ ! -e kernel/msm-5.4 ]; then
  if [ -d "$HOME/android/kernel-msm-MMI-S3RXC32.33-8-29" ]; then
    ln -sfn "$HOME/android/kernel-msm-MMI-S3RXC32.33-8-29" kernel/msm-5.4
  else
    git clone --branch "$KERNEL_BRANCH" --single-branch "$KERNEL_URL" kernel/msm-5.4
  fi
fi

echo "==> clang-r383902b1"
CLANG_DIR=prebuilts/clang/host/linux-x86
if [ ! -x "$CLANG_DIR/clang-r383902b1/bin/clang" ]; then
  if [ ! -d "$CLANG_DIR/.git" ]; then
    git clone --filter=blob:none --no-checkout "$CLANG_URL" "$CLANG_DIR"
  fi
  (
    cd "$CLANG_DIR"
    git sparse-checkout init --cone
    git sparse-checkout set clang-r383902b1
    # pinned commit used by this build tree (or latest that contains the clang)
    git checkout 225d2925 2>/dev/null || git checkout main
  )
fi

echo "==> gcc aarch64-linux-android-4.9"
GCC_DIR=prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
if [ ! -x "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
  if [ -d "$LINEAGE_ROOT/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9" ]; then
    mkdir -p prebuilts/gcc/linux-x86/aarch64
    ln -sfn "$LINEAGE_ROOT/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9" "$GCC_DIR"
  else
    echo "MISSING gcc toolchain. Set LINEAGE_ROOT or place it at:"
    echo "  $TOP/$GCC_DIR"
    exit 1
  fi
fi

echo "==> build-tools / misc (dtc, ufdt, make)"
if [ -d "$LINEAGE_ROOT/prebuilts/build-tools" ]; then
  ln -sfn "$LINEAGE_ROOT/prebuilts/build-tools" prebuilts/build-tools
else
  echo "MISSING prebuilts/build-tools (symlink from Lineage recommended)"
  exit 1
fi
if [ -d "$LINEAGE_ROOT/prebuilts/misc" ]; then
  ln -sfn "$LINEAGE_ROOT/prebuilts/misc" prebuilts/misc
else
  echo "MISSING prebuilts/misc (need dtc + ufdt_apply_overlay)"
  exit 1
fi

clone_wlan() {
  local name=$1 url=$2
  local dest="vendor/qcom/opensource/wlan/$name"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --tags origin
    git -C "$dest" checkout "$WLAN_TAG"
  else
    git clone --branch "$WLAN_TAG" --single-branch "$url" "$dest"
  fi
}

echo "==> WLAN sources @$WLAN_TAG"
clone_wlan qcacld-3.0 \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-qcacld-3.0.git
clone_wlan qca-wifi-host-cmn \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-qca-wifi-host-cmn.git
clone_wlan fw-api \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-fw-api.git

echo "==> setup done"
echo "Build with: ./build-all.sh"
