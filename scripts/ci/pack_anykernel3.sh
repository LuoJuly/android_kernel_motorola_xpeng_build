#!/usr/bin/env bash
# Pack compiled kernel Image (+ optional vendor WiFi .ko) into AnyKernel3 zip.
#
# AnyKernel3 (do.modules=1, do.systemless=0) pushes
# modules/vendor/lib/modules/*.ko onto /vendor/lib/modules/.
# The zip does NOT bundle a KernelSU/Magisk WiFi module.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work}"
DEVICE="${DEVICE:-xpeng}"
VARIANT_SLUG="${VARIANT_SLUG:-xpeng}"
AK3_REPO="${AK3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
AK3_REF="${AK3_REF:-master}"
AK3_DIR="${AK3_DIR:-${WORK_DIR}/AnyKernel3}"
WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}"

info() { echo "[+] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

gh_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "${GITHUB_ENV}"
  fi
}

resolve_image() {
  if [[ -n "${KERNEL_IMAGE:-}" && -f "${KERNEL_IMAGE}" ]]; then
    echo "${KERNEL_IMAGE}"
    return
  fi
  for cand in \
    "${WORK_DIR}/release/Image" \
    "${WORK_DIR}/release/kernel"; do
    if [[ -f "${cand}" ]]; then
      echo "${cand}"
      return
    fi
  done
  die "kernel Image not found (set KERNEL_IMAGE or build first)"
}

# Prefer qca_cld3_*.ko; also accept local MMI names wlan-*.ko in the same dir.
wlan_ko_src() {
  local dir="$1" dest_name="$2"
  if [[ -f "${dir}/${dest_name}" ]]; then
    echo "${dir}/${dest_name}"
    return
  fi
  case "${dest_name}" in
    qca_cld3_wlan.ko)
      [[ -f "${dir}/wlan-wlan.ko" ]] && { echo "${dir}/wlan-wlan.ko"; return; }
      ;;
    qca_cld3_qca6750.ko)
      [[ -f "${dir}/wlan-qca6750.ko" ]] && { echo "${dir}/wlan-qca6750.ko"; return; }
      ;;
    qca_cld3_qca6390.ko)
      [[ -f "${dir}/wlan-qca6390.ko" ]] && { echo "${dir}/wlan-qca6390.ko"; return; }
      ;;
  esac
  echo ""
}

dir_has_wlan_kos() {
  local dir="$1"
  [[ -n "$(wlan_ko_src "${dir}" qca_cld3_wlan.ko)" ]]
}

resolve_wlan_kos() {
  local dir
  for dir in \
    "${WLAN_OUT_DIR}" \
    "${WORK_DIR}/wlan-kos" \
    "${BUILD_ROOT}/out/wlan-modules"; do
    if [[ -d "${dir}" ]] && dir_has_wlan_kos "${dir}"; then
      echo "${dir}"
      return
    fi
  done
  if [[ -f "${WORK_DIR}/wlan_out_dir.txt" ]]; then
    dir="$(cat "${WORK_DIR}/wlan_out_dir.txt")"
    if [[ -d "${dir}" ]] && dir_has_wlan_kos "${dir}"; then
      echo "${dir}"
      return
    fi
  fi
  echo ""
}

clone_anykernel3() {
  local url="${AK3_REPO}"
  if [[ -n "${GITHUB_PROXY:-}" ]]; then
    case "${url}" in
      https://github.com/*) url="${GITHUB_PROXY%/}/${url}" ;;
    esac
  fi

  rm -rf "${AK3_DIR}"
  info "Cloning AnyKernel3 (${AK3_REF}) from ${url}"
  git clone --depth=1 --branch "${AK3_REF}" "${url}" "${AK3_DIR}"
  AK3_COMMIT="$(git -C "${AK3_DIR}" rev-parse --short=8 HEAD)"
  AK3_DESCRIBE="$(git -C "${AK3_DIR}" describe --tags --always 2>/dev/null || echo "${AK3_COMMIT}")"
  export AK3_COMMIT AK3_DESCRIBE
  printf '%s\n' "${AK3_COMMIT}" > "${WORK_DIR}/ak3_commit.txt"
  gh_env AK3_COMMIT "${AK3_COMMIT}"
  info "AnyKernel3: ${AK3_DESCRIBE} (${AK3_COMMIT})"
}

write_anykernel_sh() {
  local resukisu_ver="${RESUKISU_DISPLAY:-${RESUKISU_VERSION:-unknown}}"
  local rom_id="${ROM_ID:-S3RXC32.33-8-29}"
  local device_title="${DEVICE_TITLE:-${DEVICE}}"
  local has_wlan="${1:-0}"
  cat > "${AK3_DIR}/anykernel.sh" <<EOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Auto-generated for ${device_title} ReSukiSU

### AnyKernel setup
# global properties
properties() { '
kernel.string=${device_title} ${resukisu_ver} (${rom_id})
do.devicecheck=1
do.modules=1
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=${DEVICE}
device.name2=xpeng
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 \$RAMDISK/*;
set_perm_recursive 0 0 750 750 \$RAMDISK/init* \$RAMDISK/sbin;
} # end attributes

# boot shell variables (A/B device, kernel-only replace)
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

ui_print " ";
ui_print "Kernel: ${resukisu_ver}";
ui_print "Device: ${device_title}";

# boot install: replace kernel only (keep ROM ramdisk) for broad ROM compatibility
split_boot;
flash_boot;

EOF

  if [[ "${has_wlan}" == "1" ]]; then
    cat >> "${AK3_DIR}/anykernel.sh" <<'EOF'
ui_print " ";
ui_print "WiFi qca_cld3_*.ko will be pushed to /vendor/lib/modules/";
ui_print "(do.modules=1, no KernelSU WiFi module required)";
EOF
  fi

  cat >> "${AK3_DIR}/anykernel.sh" <<'EOF'
## end boot install
EOF
}

stage_wlan_kos() {
  local wlan_dir="$1"
  local dest="${AK3_DIR}/modules/vendor/lib/modules"
  local dest_name src missing=0
  mkdir -p "${dest}"
  for dest_name in qca_cld3_wlan.ko qca_cld3_qca6750.ko qca_cld3_qca6390.ko; do
    src="$(wlan_ko_src "${wlan_dir}" "${dest_name}")"
    if [[ -n "${src}" && -f "${src}" ]]; then
      cp -f "${src}" "${dest}/${dest_name}"
      info "Staged ${src} -> modules/vendor/lib/modules/${dest_name}"
    else
      info "WARNING: missing ${dest_name} in ${wlan_dir}"
      missing=1
    fi
  done
  [[ "${missing}" == "0" ]] || die "incomplete WiFi kos in ${wlan_dir}"
}

pack_zip() {
  local image="$1"
  local wlan_dir="${2:-}"
  mkdir -p "${WORK_DIR}/release"

  rm -rf "${AK3_DIR}/.git" \
         "${AK3_DIR}/modules/"* \
         "${AK3_DIR}/patch/"* \
         "${AK3_DIR}/ramdisk/"* 2>/dev/null || true
  mkdir -p "${AK3_DIR}/modules" "${AK3_DIR}/patch" "${AK3_DIR}/ramdisk"

  cp -f "${image}" "${AK3_DIR}/Image"

  if [[ -n "${wlan_dir}" && -d "${wlan_dir}" ]]; then
    stage_wlan_kos "${wlan_dir}"
  fi

  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt" 2>/dev/null || echo unknown)}"
  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  ROM_ID="${ROM_ID:-$(cat "${WORK_DIR}/rom_id.txt" 2>/dev/null || echo S3RXC32.33-8-29)}"
  local safe_ver
  safe_ver="$(echo "${RESUKISU_VERSION}" | tr '/:' '--')"
  local zip_name="AnyKernel3-${VARIANT_SLUG}-ReSukiSU-${safe_ver}-${ROM_ID}.zip"
  local zip_path="${WORK_DIR}/release/${zip_name}"

  rm -f "${zip_path}"
  (
    cd "${AK3_DIR}"
    zip -r9 "${zip_path}" . \
      -x '*.git*' \
      -x 'README.md' \
      -x 'LICENSE' \
      -x '*.md'
  )
  [[ -f "${zip_path}" ]] || die "failed to create ${zip_path}"

  cp -f "${zip_path}" "${WORK_DIR}/release/AnyKernel3.zip"

  AK3_ZIP="${zip_path}"
  export AK3_ZIP
  gh_env AK3_ZIP "${AK3_ZIP}"
  gh_env AK3_COMMIT "${AK3_COMMIT:-}"
  info "AnyKernel3 zip: ${AK3_ZIP} ($(du -h "${AK3_ZIP}" | awk '{print $1}'))"
}

main() {
  command -v zip >/dev/null || die "zip is required (apt install zip)"
  command -v git >/dev/null || die "git is required"

  local image wlan_dir has_wlan=0
  image="$(resolve_image)"
  info "Using kernel Image: ${image}"
  wlan_dir="$(resolve_wlan_kos)"
  if [[ -n "${wlan_dir}" ]]; then
    has_wlan=1
    info "Packing WiFi kos from: ${wlan_dir}"
  else
    info "No WiFi kos found; packing kernel-only AnyKernel3"
  fi

  if [[ -z "${RESUKISU_VERSION:-}" && -f "${WORK_DIR}/resukisu_version.txt" ]]; then
    RESUKISU_VERSION="$(cat "${WORK_DIR}/resukisu_version.txt")"
  fi
  if [[ -z "${RESUKISU_DISPLAY:-}" && -f "${WORK_DIR}/resukisu_display.txt" ]]; then
    RESUKISU_DISPLAY="$(cat "${WORK_DIR}/resukisu_display.txt")"
  fi
  if [[ -z "${ROM_ID:-}" && -f "${WORK_DIR}/rom_id.txt" ]]; then
    ROM_ID="$(cat "${WORK_DIR}/rom_id.txt")"
  fi
  export RESUKISU_VERSION RESUKISU_DISPLAY ROM_ID

  clone_anykernel3
  write_anykernel_sh "${has_wlan}"
  pack_zip "${image}" "${wlan_dir}"
  info "AnyKernel3 pack done."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
