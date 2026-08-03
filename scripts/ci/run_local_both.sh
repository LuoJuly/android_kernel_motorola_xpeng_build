#!/usr/bin/env bash
# Local helper: build both Edge S30 (no NFC) and G200 (NFC) variants.
set -euo pipefail

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${BUILD_ROOT}"

chmod +x scripts/ci/build_resukisu_boot.sh scripts/ci/pack_anykernel3.sh
chmod +x scripts/ci/host-bin/* 2>/dev/null || true

export XPENG_BUILD_ROOT="${XPENG_BUILD_ROOT:-${BUILD_ROOT}}"
export UPDATE_RESUKISU="${UPDATE_RESUKISU:-true}"
export BOOT_OEM_IMG="${BOOT_OEM_IMG:-${BUILD_ROOT}/prebuilt/boot_oem.img}"
export KERNEL_URL="${KERNEL_URL:-https://github.com/LuoJuly/android_kernel_motorola_xpeng.git}"
export KERNEL_BRANCH="${KERNEL_BRANCH:-android-12-release-S3RXC32.33-8-29}"

if [[ ! -f "${BOOT_OEM_IMG}" && -f "${HOME}/下载/boot_oem.img" ]]; then
  mkdir -p "${BUILD_ROOT}/prebuilt"
  cp -f "${HOME}/下载/boot_oem.img" "${BUILD_ROOT}/prebuilt/boot_oem.img"
  BOOT_OEM_IMG="${BUILD_ROOT}/prebuilt/boot_oem.img"
fi

# Prefer local kernel tree for faster local runs (still git-backed, not uploaded)
if [[ -z "${KERNEL_SRC:-}" && -d "${BUILD_ROOT}/kernel/msm-5.4/.git" ]]; then
  export KERNEL_SRC="$(cd "${BUILD_ROOT}/kernel/msm-5.4" && pwd -P)"
elif [[ -z "${KERNEL_SRC:-}" && -d "${HOME}/android/kernel-msm-MMI-S3RXC32.33-8-29/.git" ]]; then
  export KERNEL_SRC="${HOME}/android/kernel-msm-MMI-S3RXC32.33-8-29"
fi

echo "======== Edge S30 (XT2175-2, NFC off) ========"
VARIANT=edge-s30 UPDATE_RESUKISU="${UPDATE_RESUKISU}" \
  XPENG_BUILD_ROOT="${XPENG_BUILD_ROOT}" \
  BOOT_OEM_IMG="${BOOT_OEM_IMG}" \
  KERNEL_SRC="${KERNEL_SRC:-}" \
  scripts/ci/build_resukisu_boot.sh

echo "======== G200 (XT2175-1, NFC on) ========"
# ReSukiSU already updated in the first build
VARIANT=g200 UPDATE_RESUKISU=false \
  XPENG_BUILD_ROOT="${XPENG_BUILD_ROOT}" \
  BOOT_OEM_IMG="${BOOT_OEM_IMG}" \
  KERNEL_SRC="${KERNEL_SRC:-}" \
  scripts/ci/build_resukisu_boot.sh

echo "======== ALL LOCAL BUILDS DONE ========"
ls -lh .ci-work/edge-s30/release/ .ci-work/g200/release/
