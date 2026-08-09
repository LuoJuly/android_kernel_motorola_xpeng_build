#!/usr/bin/env bash
# Pack compiled kernel Image (+ optional WiFi KSU Magisk module) into AnyKernel3 zip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work}"
DEVICE="${DEVICE:-xpeng}"
VARIANT_SLUG="${VARIANT_SLUG:-xpeng}"
KERNEL_VER_LABEL="${KERNEL_VER_LABEL:-5.4.302}"
AK3_REPO="${AK3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
AK3_REF="${AK3_REF:-master}"
AK3_DIR="${AK3_DIR:-${WORK_DIR}/AnyKernel3}"
WLAN_KSU_ZIP="${WLAN_KSU_ZIP:-}"
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

resolve_wlan_zip() {
  if [[ -n "${WLAN_KSU_ZIP}" && -f "${WLAN_KSU_ZIP}" ]]; then
    echo "${WLAN_KSU_ZIP}"
    return
  fi
  if [[ -f "${WORK_DIR}/wlan_ksu_zip.txt" ]]; then
    local p
    p="$(cat "${WORK_DIR}/wlan_ksu_zip.txt")"
    if [[ -f "${p}" ]]; then
      echo "${p}"
      return
    fi
  fi
  if [[ -f "${WORK_DIR}/release/wlan_crc_match_ksu.zip" ]]; then
    echo "${WORK_DIR}/release/wlan_crc_match_ksu.zip"
    return
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
  local rom_id="${ROM_ID:-S3RXC32.33-8-25}"
  local device_title="${DEVICE_TITLE:-${DEVICE}}"
  local kver="${KERNEL_VER_LABEL}"
  local has_wlan="${1:-0}"
  cat > "${AK3_DIR}/anykernel.sh" <<EOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Auto-generated for ${device_title} ReSukiSU (${kver})

### AnyKernel setup
# global properties
properties() { '
kernel.string=${device_title} ${kver} ${resukisu_ver} (${rom_id})
do.devicecheck=1
do.modules=0
do.systemless=1
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
ui_print "Kernel: ${kver} / ${resukisu_ver}";
ui_print "Device: ${device_title}";

# boot install: replace kernel only (keep ROM ramdisk) for broad ROM compatibility
split_boot;
flash_boot;

EOF

  if [[ "${has_wlan}" == "1" ]]; then
    cat >> "${AK3_DIR}/anykernel.sh" <<'EOF'
## bundled WiFi KSU Magisk module (CRC/vermagic-matched qca_cld3_*.ko)
ui_print " ";
ui_print "Installing bundled WiFi KSU module...";
WLAN_ZIP="$AKHOME/wlan_crc_match_ksu.zip";
if [ -f "$WLAN_ZIP" ]; then
  # Persist a copy for KernelSU Manager / manual install
  mkdir -p /sdcard/Download;
  cp -f "$WLAN_ZIP" /sdcard/Download/wlan_crc_match_ksu.zip;
  ui_print "- saved /sdcard/Download/wlan_crc_match_ksu.zip";

  # Best-effort install into Magisk/KernelSU modules dir (when writable)
  MODROOT="";
  for d in /data/adb/modules /data/adb/ksu/modules; do
    if [ -d "$(dirname "$d")" ] && mkdir -p "$d" 2>/dev/null; then
      MODROOT="$d/wlan_crc_match_302";
      break;
    fi
  done
  if [ -n "$MODROOT" ]; then
    rm -rf "$MODROOT";
    mkdir -p "$MODROOT";
    unzip -o "$WLAN_ZIP" -d "$MODROOT" >/dev/null 2>&1 || true;
    # Magisk update-binary / META-INF not needed inside modules tree
    rm -rf "$MODROOT/META-INF" 2>/dev/null || true;
    chmod 0755 "$MODROOT/service.sh" "$MODROOT/customize.sh" 2>/dev/null || true;
    touch "$MODROOT/auto_mount" 2>/dev/null || true;
    ui_print "- installed module -> $MODROOT";
    ui_print "- reboot required for Wi-Fi overlay + service.sh";
  else
    ui_print "- /data not writable here; install wlan_crc_match_ksu.zip via KernelSU after boot";
  fi
else
  ui_print "- WARNING: wlan_crc_match_ksu.zip missing from zip";
fi
## end WiFi module install
EOF
  fi

  cat >> "${AK3_DIR}/anykernel.sh" <<'EOF'
## end boot install
EOF
}

pack_zip() {
  local image="$1"
  local wlan_zip="${2:-}"
  mkdir -p "${WORK_DIR}/release"

  rm -rf "${AK3_DIR}/.git" \
         "${AK3_DIR}/modules/"* \
         "${AK3_DIR}/patch/"* \
         "${AK3_DIR}/ramdisk/"* 2>/dev/null || true
  mkdir -p "${AK3_DIR}/modules" "${AK3_DIR}/patch" "${AK3_DIR}/ramdisk"

  cp -f "${image}" "${AK3_DIR}/Image"

  if [[ -n "${wlan_zip}" && -f "${wlan_zip}" ]]; then
    cp -f "${wlan_zip}" "${AK3_DIR}/wlan_crc_match_ksu.zip"
    # Also stage kos under modules/ for visibility / optional tools
    if [[ -d "${WLAN_OUT_DIR}" ]]; then
      mkdir -p "${AK3_DIR}/modules/system/vendor/lib/modules"
      cp -f "${WLAN_OUT_DIR}/qca_cld3_"*.ko \
        "${AK3_DIR}/modules/system/vendor/lib/modules/" 2>/dev/null || true
    fi
  fi

  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt" 2>/dev/null || echo unknown)}"
  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  ROM_ID="${ROM_ID:-$(cat "${WORK_DIR}/rom_id.txt" 2>/dev/null || echo S3RXC32.33-8-25)}"
  local safe_ver
  safe_ver="$(echo "${RESUKISU_VERSION}" | tr '/:' '--')"
  local zip_name="AnyKernel3-${VARIANT_SLUG}-ReSukiSU-${KERNEL_VER_LABEL}-${safe_ver}-${ROM_ID}.zip"
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

  local image wlan_zip has_wlan=0
  image="$(resolve_image)"
  info "Using kernel Image: ${image}"
  wlan_zip="$(resolve_wlan_zip)"
  if [[ -n "${wlan_zip}" ]]; then
    has_wlan=1
    info "Bundling WiFi KSU zip: ${wlan_zip}"
  else
    info "No WiFi KSU zip found; packing kernel-only AnyKernel3"
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
  export RESUKISU_VERSION RESUKISU_DISPLAY ROM_ID KERNEL_VER_LABEL

  clone_anykernel3
  write_anykernel_sh "${has_wlan}"
  pack_zip "${image}" "${wlan_zip}"
  info "AnyKernel3 pack done."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
