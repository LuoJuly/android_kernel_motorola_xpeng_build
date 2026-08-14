#!/usr/bin/env bash
# Build qcacld-3.0 wlan.ko (3 chips) against a finished kernel O= tree for CI.
# Expects toolchain vars from build_resukisu_boot.sh (CLANG, MAKE, ...).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
OUT_DIR="${OUT_DIR:?OUT_DIR required (kernel O= tree)}"
WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work}"
WLAN_TAG="${WLAN_TAG:-MMI-S3RXC32.33-8-29}"
WLAN_BLD_DIR="${WLAN_BLD_DIR:-${BUILD_ROOT}/vendor/qcom/opensource/wlan}"
WLAN_ROOT="${WLAN_ROOT:-${WLAN_BLD_DIR}/qcacld-3.0}"
WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}"
JOBS="${JOBS:-$(nproc)}"

info() { echo "[+] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

[[ -f "${OUT_DIR}/Makefile" ]] || die "kernel out missing: ${OUT_DIR}/Makefile"
[[ -n "${CLANG:-}" && -x "${CLANG}" ]] || die "CLANG not set (run setup_toolchain first)"
[[ -n "${MAKE:-}" && -x "${MAKE}" ]] || die "MAKE not set"
[[ -n "${AARCH64_PREFIX:-}" ]] || die "AARCH64_PREFIX not set"
[[ -n "${LD_LLD:-}" && -x "${LD_LLD}" ]] || die "LD_LLD not set"
[[ -n "${LLVM_AR:-}" && -x "${LLVM_AR}" ]] || die "LLVM_AR not set"
[[ -n "${LLVM_NM:-}" && -x "${LLVM_NM}" ]] || die "LLVM_NM not set"
[[ -n "${DTC_EXT:-}" && -x "${DTC_EXT}" ]] || die "DTC_EXT not set"
[[ -n "${UFDT_EXT:-}" && -x "${UFDT_EXT}" ]] || die "UFDT_EXT not set"

LLVM_STRIP="${LLVM_STRIP:-$(dirname "${CLANG}")/llvm-strip}"
[[ -x "${LLVM_STRIP}" ]] || die "llvm-strip missing: ${LLVM_STRIP}"

fetch_wlan() {
  local name=$1 url=$2
  local dest="${WLAN_BLD_DIR}/${name}"
  mkdir -p "${WLAN_BLD_DIR}"
  if [[ -d "${dest}/.git" ]]; then
    info "Updating WLAN ${name} @ ${WLAN_TAG}"
    git -C "${dest}" fetch --tags origin 2>/dev/null || true
    git -C "${dest}" checkout -f "${WLAN_TAG}" 2>/dev/null \
      || git -C "${dest}" checkout -f "tags/${WLAN_TAG}" 2>/dev/null \
      || die "cannot checkout ${WLAN_TAG} in ${dest}"
  else
    info "Cloning WLAN ${name} @ ${WLAN_TAG}"
    rm -rf "${dest}"
    git clone --branch "${WLAN_TAG}" --single-branch --depth=1 "${url}" "${dest}" \
      || git clone --branch "${WLAN_TAG}" --single-branch "${url}" "${dest}"
  fi
}

info "Fetch WLAN sources (${WLAN_TAG})"
fetch_wlan qcacld-3.0 \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-qcacld-3.0.git
fetch_wlan qca-wifi-host-cmn \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-qca-wifi-host-cmn.git
fetch_wlan fw-api \
  https://github.com/MotorolaMobilityLLC/vendor-qcom-opensource-wlan-fw-api.git

[[ -d "${WLAN_ROOT}" ]] || die "missing ${WLAN_ROOT}"

info "Setup per-chip build trees"
target_chip=(qca6750 qca6390 wlan)
(
  cd "${WLAN_ROOT}"
  for chip in "${target_chip[@]}"; do
    mkdir -vp "${WLAN_ROOT}/.${chip}"
    ln -sfn "${WLAN_BLD_DIR}/qca-wifi-host-cmn" "${WLAN_ROOT}/.${chip}/qca-wifi-host-cmn"
    while IFS= read -r -d '' node; do
      base=$(basename "${node}")
      case "${base}" in .|..|.*|*~) continue ;; esac
      ln -sfn "${WLAN_ROOT}/${base}" "${WLAN_ROOT}/.${chip}/${base}"
    done < <(find "${WLAN_ROOT}" -mindepth 1 -maxdepth 1 -print0)
  done
)

export ANDROID_BUILD_TOP="${BUILD_ROOT}"
export PATH="$(dirname "${CLANG}"):${BUILD_ROOT}/bin:${PATH:-}"

COMMON=(
  ARCH=arm64
  CROSS_COMPILE="${AARCH64_PREFIX}"
  REAL_CC="${CLANG}"
  CLANG_TRIPLE=aarch64-linux-gnu-
  AR="${LLVM_AR}"
  LLVM_NM="${LLVM_NM}"
  LD="${LD_LLD}"
  NM="${LLVM_NM}"
  DTC_EXT="${DTC_EXT}"
  DTC_OVERLAY_TEST_EXT="${UFDT_EXT}"
  CONFIG_BUILD_ARM64_DT_OVERLAY=y
  HOSTCC="${CLANG}"
  HOSTAR="${LLVM_AR}"
  HOSTLD="${LD_LLD}"
  WLAN_COMMON_ROOT=./qca-wifi-host-cmn
  WLAN_COMMON_INC=vendor/qcom/opensource/wlan/qca-wifi-host-cmn
  WLAN_FW_API=vendor/qcom/opensource/wlan/fw-api
  WLAN_PROFILE=default
  MODNAME=wlan
  BOARD_PLATFORM=lahaina
  CONFIG_QCA_CLD_WLAN=m
  ANDROID_BUILD_TOP="${BUILD_ROOT}"
)

build_chip() {
  local chip=$1 cnss_flag=$2
  local mdir="${WLAN_ROOT}/.${chip}"
  info "Build chip=${chip}"
  # Force rebuild against current Module.symvers / vermagic
  find "${mdir}" \( -name '*.o' -o -name '*.ko' -o -name '.*.cmd' -o -name '*.mod' -o -name '*.mod.c' -o -name '*.lto.o' \) -delete 2>/dev/null || true
  "${MAKE}" -j"${JOBS}" -C "${OUT_DIR}" M="${mdir}" \
    "${COMMON[@]}" \
    modules \
    WLAN_ROOT="vendor/qcom/opensource/wlan/qcacld-3.0/.${chip}" \
    DYNAMIC_SINGLE_CHIP="${chip}" \
    DEVNAME="${chip}" \
    "${cnss_flag}"
  [[ -f "${mdir}/wlan.ko" ]] || die "missing ${mdir}/wlan.ko"
}

build_chip wlan 'CONFIG_CNSS_QCA6490=y'
build_chip qca6750 'CONFIG_CNSS_QCA6750=y'
build_chip qca6390 'CONFIG_CNSS_QCA6390=y'

mkdir -p "${WLAN_OUT_DIR}"
cp -f "${WLAN_ROOT}/.wlan/wlan.ko" "${WLAN_OUT_DIR}/qca_cld3_wlan.ko"
cp -f "${WLAN_ROOT}/.qca6750/wlan.ko" "${WLAN_OUT_DIR}/qca_cld3_qca6750.ko"
cp -f "${WLAN_ROOT}/.qca6390/wlan.ko" "${WLAN_OUT_DIR}/qca_cld3_qca6390.ko"

info "Strip modules"
for ko in qca_cld3_wlan.ko qca_cld3_qca6750.ko qca_cld3_qca6390.ko; do
  "${LLVM_STRIP}" --strip-debug "${WLAN_OUT_DIR}/${ko}" || \
    "${LLVM_STRIP}" -g "${WLAN_OUT_DIR}/${ko}" || true
done

info "WLAN modules ready in ${WLAN_OUT_DIR}"
ls -lh "${WLAN_OUT_DIR}"
modinfo "${WLAN_OUT_DIR}/qca_cld3_wlan.ko" | head -12 || true
printf '%s\n' "${WLAN_OUT_DIR}" > "${WORK_DIR}/wlan_out_dir.txt"
