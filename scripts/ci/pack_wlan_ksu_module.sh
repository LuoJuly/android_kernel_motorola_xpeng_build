#!/usr/bin/env bash
# Pack stripped qca_cld3_*.ko into a Magisk/KernelSU flashable zip (CRC/vermagic matched).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work}"
WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}"
TEMPLATE_DIR="${TEMPLATE_DIR:-${SCRIPT_DIR}/wlan-ksu-module-template}"
KERNEL_VER_LABEL="${KERNEL_VER_LABEL:-5.4.302}"
KERNEL_SRC="${KERNEL_SRC:-${KERNEL_DIR:-}}"

info() { echo "[+] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

gh_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "${GITHUB_ENV}"
  fi
}

command -v zip >/dev/null || die "zip is required"
[[ -d "${TEMPLATE_DIR}" ]] || die "missing template ${TEMPLATE_DIR}"
for ko in qca_cld3_wlan.ko qca_cld3_qca6750.ko qca_cld3_qca6390.ko; do
  [[ -f "${WLAN_OUT_DIR}/${ko}" ]] || die "missing ${WLAN_OUT_DIR}/${ko}"
done

mkdir -p "${WORK_DIR}/release"
STAGE="${WORK_DIR}/wlan-ksu-module-stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/system/vendor/lib/modules"
mkdir -p "${STAGE}/META-INF/com/google/android"

cp -a "${TEMPLATE_DIR}/META-INF/com/google/android/." "${STAGE}/META-INF/com/google/android/"
cp -f "${TEMPLATE_DIR}/customize.sh" "${STAGE}/customize.sh"
cp -f "${TEMPLATE_DIR}/service.sh" "${STAGE}/service.sh"
cp -f "${TEMPLATE_DIR}/README.txt" "${STAGE}/README.txt"
chmod 0755 "${STAGE}/service.sh" "${STAGE}/customize.sh" \
  "${STAGE}/META-INF/com/google/android/update-binary" || true

cp -f "${WLAN_OUT_DIR}/qca_cld3_wlan.ko" "${STAGE}/system/vendor/lib/modules/"
cp -f "${WLAN_OUT_DIR}/qca_cld3_qca6750.ko" "${STAGE}/system/vendor/lib/modules/"
cp -f "${WLAN_OUT_DIR}/qca_cld3_qca6390.ko" "${STAGE}/system/vendor/lib/modules/"

vermagic="$(modinfo -F vermagic "${WLAN_OUT_DIR}/qca_cld3_wlan.ko" 2>/dev/null || true)"
kernel_sha="unknown"
if [[ -n "${KERNEL_SRC}" && -d "${KERNEL_SRC}/.git" ]]; then
  kernel_sha="$(git -C "${KERNEL_SRC}" rev-parse --short=12 HEAD)"
elif [[ -n "${KERNEL_DIR:-}" && -d "${KERNEL_DIR}/.git" ]]; then
  kernel_sha="$(git -C "${KERNEL_DIR}" rev-parse --short=12 HEAD)"
fi
# Prefer vermagic embedded gSHA if present
if [[ "${vermagic}" =~ g([0-9a-f]{7,}) ]]; then
  kernel_sha="${BASH_REMATCH[1]}"
fi
safe_sha="$(echo "${kernel_sha}" | tr -c 'A-Za-z0-9._-' '_')"

cat > "${STAGE}/module.prop" <<EOF
id=wlan_crc_match_302
name=qcacld CRC-matched WiFi for ${KERNEL_VER_LABEL}
version=v1.0.${KERNEL_VER_LABEL##*.}-g${safe_sha}
versionCode=${KERNEL_VER_LABEL##*.}
author=xpeng-resukisu-ci
description=Optional overlay of qca_cld3_{wlan,qca6750,qca6390}.ko (${vermagic:-${KERNEL_VER_LABEL}}, MODVERSIONS=y). Not needed after flashing AnyKernel3 (do.modules=1 replaces vendor kos). Use only if you flashed boot_ksu.img via fastboot.
EOF

zip_name="wlan_crc_match_${KERNEL_VER_LABEL}-ksu-g${safe_sha}.zip"
zip_path="${WORK_DIR}/release/${zip_name}"
rm -f "${zip_path}"
(
  cd "${STAGE}"
  zip -r9 "${zip_path}" .
)
[[ -f "${zip_path}" ]] || die "failed to create ${zip_path}"
cp -f "${zip_path}" "${WORK_DIR}/release/wlan_crc_match_ksu.zip"

WLAN_KSU_ZIP="${zip_path}"
export WLAN_KSU_ZIP
printf '%s\n' "${WLAN_KSU_ZIP}" > "${WORK_DIR}/wlan_ksu_zip.txt"
gh_env WLAN_KSU_ZIP "${WLAN_KSU_ZIP}"
info "WLAN KSU zip: ${WLAN_KSU_ZIP} ($(du -h "${WLAN_KSU_ZIP}" | awk '{print $1}'))"
info "vermagic: ${vermagic:-unknown}"
