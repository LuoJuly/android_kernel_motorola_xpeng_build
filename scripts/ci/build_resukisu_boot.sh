#!/usr/bin/env bash
# Build xpeng MMI kernel (ReSukiSU), repack boot_oem.img, pack AnyKernel3
# (do.modules=1 pushes vendor WiFi kos when present; no KSU wifi zip inside AK3).
#
# This script lives in kernel_motorola_xpeng_build and clones kernel sources
# from github.com/LuoJuly/android_kernel_motorola_xpeng (not vendored here).
#
# Variants:
#   VARIANT=edge-s30  ENABLE_NFC=false  -> Moto Edge S30 (XT2175-2)
#   VARIANT=g200      ENABLE_NFC=true   -> Moto G200 5G (XT2175-1)
set -euo pipefail

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${BUILD_ROOT}"

VARIANT="${VARIANT:-edge-s30}"
ENABLE_NFC="${ENABLE_NFC:-false}"
ROM_ID="${ROM_ID:-S3RXC32.33-8-29}"
DEVICE="${DEVICE:-xpeng}"
TARGET_PRODUCT="${TARGET_PRODUCT:-xpeng_retcn}"
TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-user}"
CLANG_VERSION="${CLANG_VERSION:-clang-r383902b1}"
CLANG_GIT_URL="${CLANG_GIT_URL:-https://mirrors.bfsu.edu.cn/git/AOSP/platform/prebuilts/clang/host/linux-x86}"
CLANG_GIT_FALLBACK="${CLANG_GIT_FALLBACK:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86}"
# AOSP main tip is empty; use Lineage mirror (same as local xpeng-build/setup.sh).
GCC_GIT_URL="${GCC_GIT_URL:-https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git}"
GCC_GIT_BRANCH="${GCC_GIT_BRANCH:-lineage-19.1}"
GCC_GIT_FALLBACK="${GCC_GIT_FALLBACK:-https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9}"
GCC_GIT_FALLBACK_BRANCH="${GCC_GIT_FALLBACK_BRANCH:-master-kernel-build-2021}"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-${BUILD_ROOT}/.ci-toolchain}"
XPENG_BUILD_ROOT="${XPENG_BUILD_ROOT:-${BUILD_ROOT}}"
JOBS="${JOBS:-$(nproc)}"
BOOT_OEM_IMG="${BOOT_OEM_IMG:-${BUILD_ROOT}/prebuilt/boot_oem.img}"
# Large OEM boot is kept as a Release asset (not in git) to avoid flaky huge pushes.
BOOT_OEM_RELEASE_REPO="${BOOT_OEM_RELEASE_REPO:-LuoJuly/kernel_motorola_xpeng_build}"
# Tag prefix z- keeps this utility release at the bottom of the Releases list.
BOOT_OEM_RELEASE_TAG="${BOOT_OEM_RELEASE_TAG:-z-assets-S3RXC32.33-8-29}"
BOOT_OEM_ASSET_NAME="${BOOT_OEM_ASSET_NAME:-boot_oem.img}"

KERNEL_URL="${KERNEL_URL:-https://github.com/LuoJuly/android_kernel_motorola_xpeng.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-android-12-release-S3RXC32.33-8-29}"
KERNEL_DIR="${KERNEL_DIR:-${BUILD_ROOT}/.ci-src/android_kernel_motorola_xpeng}"

case "${VARIANT}" in
  edge-s30|edges30|xt2175-2)
    VARIANT=edge-s30
    VARIANT_SLUG="xpeng-EdgeS30"
    DEVICE_TITLE="Moto Edge S30 (XT2175-2)"
    RELEASE_TITLE="xpeng ReSukiSU Boot/Kernel for Moto Edge S30 (XT2175-2)"
    ENABLE_NFC=false
    ;;
  g200|xt2175-1)
    VARIANT=g200
    VARIANT_SLUG="xpeng-G200"
    DEVICE_TITLE="Moto G200 5G (XT2175-1)"
    RELEASE_TITLE="xpeng ReSukiSU Boot/Kernel for Moto G200 5G (XT2175-1)"
    ENABLE_NFC=true
    ;;
  *)
    echo "[!] Unknown VARIANT=${VARIANT} (use edge-s30 or g200)" >&2
    exit 1
    ;;
esac

WORK_DIR="${WORK_DIR:-${BUILD_ROOT}/.ci-work/${VARIANT}}"
OUT_DIR="${OUT_DIR:-${BUILD_ROOT}/out/${VARIANT}}"
HOST_BIN_DIR="${BUILD_ROOT}/scripts/ci/host-bin"

mkdir -p "${TOOLCHAIN_DIR}" "${OUT_DIR}" "${WORK_DIR}"
mkdir -p "${WORK_DIR}/boot" "${WORK_DIR}/release" "$(dirname "${KERNEL_DIR}")"

log() { echo "::group::$1"; }
endlog() { echo "::endgroup::"; }
info() { echo "[+] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

curl_get() {
  curl -L --http1.1 --retry 5 --retry-all-errors --retry-delay 3 "$@"
}

gh_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "${GITHUB_ENV}"
  fi
}

# ---------------------------------------------------------------------------
# 1) Fetch kernel sources (git only; not uploaded in this repo)
# ---------------------------------------------------------------------------
fetch_kernel() {
  log "Fetch kernel source (${KERNEL_BRANCH})"

  if [[ -n "${KERNEL_SRC:-}" && -d "${KERNEL_SRC}/.git" ]]; then
    KERNEL_DIR="$(cd "${KERNEL_SRC}" && pwd)"
    info "Using existing KERNEL_SRC=${KERNEL_DIR}"
  elif [[ -d "${KERNEL_DIR}/.git" ]]; then
    info "Updating existing clone at ${KERNEL_DIR}"
    git -C "${KERNEL_DIR}" fetch --tags origin
    git -C "${KERNEL_DIR}" checkout -f "${KERNEL_BRANCH}"
    git -C "${KERNEL_DIR}" reset --hard "origin/${KERNEL_BRANCH}" 2>/dev/null \
      || git -C "${KERNEL_DIR}" reset --hard "${KERNEL_BRANCH}"
    git -C "${KERNEL_DIR}" submodule sync --recursive
    git -C "${KERNEL_DIR}" submodule update --init --recursive
  else
    # Prefer local symlink/tree used by setup.sh to avoid re-cloning on local hosts
    local local_link="${BUILD_ROOT}/kernel/msm-5.4"
    if [[ -d "${local_link}/.git" || -d "${local_link}/KernelSU" ]]; then
      local resolved
      resolved="$(cd "${local_link}" && pwd -P)"
      if [[ -d "${resolved}/.git" ]]; then
        KERNEL_DIR="${resolved}"
        info "Using local kernel tree via kernel/msm-5.4 -> ${KERNEL_DIR}"
      fi
    fi

    if [[ ! -d "${KERNEL_DIR}/.git" ]]; then
      info "git clone --recursive --branch ${KERNEL_BRANCH} ${KERNEL_URL}"
      rm -rf "${KERNEL_DIR}"
      git clone --recursive --branch "${KERNEL_BRANCH}" --single-branch \
        "${KERNEL_URL}" "${KERNEL_DIR}"
    fi
  fi

  [[ -d "${KERNEL_DIR}" ]] || die "kernel dir missing: ${KERNEL_DIR}"
  [[ -f "${KERNEL_DIR}/Makefile" ]] || die "not a kernel tree: ${KERNEL_DIR}"
  info "KERNEL_DIR=${KERNEL_DIR}"
  gh_env KERNEL_DIR "${KERNEL_DIR}"
  export KERNEL_DIR
  endlog
}

# ---------------------------------------------------------------------------
# 2) Update ReSukiSU submodule
# ---------------------------------------------------------------------------
update_resukisu() {
  log "Update ReSukiSU submodule"
  cd "${KERNEL_DIR}"

  if [[ ! -e KernelSU/.git ]]; then
    git submodule update --init --recursive KernelSU
  fi

  if [[ "${UPDATE_RESUKISU:-true}" == "true" ]]; then
    git -C KernelSU fetch --unshallow origin 2>/dev/null || true
    git -C KernelSU fetch origin main --tags --force
    git -C KernelSU checkout -f origin/main
    info "ReSukiSU updated to origin/main"
  else
    info "ReSukiSU kept at current checkout (UPDATE_RESUKISU=false)"
  fi

  RESUKISU_VERSION="$(git -C KernelSU describe --tags --always)"
  RESUKISU_SHA="$(git -C KernelSU rev-parse --short=8 HEAD)"
  local ksu_count
  ksu_count="$(git -C KernelSU rev-list --count HEAD)"
  KSU_VERSION="$((30000 + ksu_count + 700))"
  KSU_UAPI_VERSION="$(
    sed -nE 's/.*KERNEL_SU_UAPI_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' \
      KernelSU/uapi/supercall.h 2>/dev/null | head -1
  )"
  KSU_UAPI_VERSION="${KSU_UAPI_VERSION:-2}"
  # e.g. v4.1.0-1332-g59c99fdf@ReSukiSU (35046/2)
  RESUKISU_DISPLAY="${RESUKISU_VERSION}@ReSukiSU (${KSU_VERSION}/${KSU_UAPI_VERSION})"

  info "ReSukiSU: ${RESUKISU_DISPLAY}"
  gh_env RESUKISU_VERSION "${RESUKISU_VERSION}"
  gh_env RESUKISU_SHA "${RESUKISU_SHA}"
  gh_env KSU_VERSION "${KSU_VERSION}"
  gh_env KSU_UAPI_VERSION "${KSU_UAPI_VERSION}"
  gh_env RESUKISU_DISPLAY "${RESUKISU_DISPLAY}"
  export RESUKISU_VERSION RESUKISU_SHA KSU_VERSION KSU_UAPI_VERSION RESUKISU_DISPLAY
  printf '%s\n' "${RESUKISU_VERSION}" > "${WORK_DIR}/resukisu_version.txt"
  printf '%s\n' "${RESUKISU_DISPLAY}" > "${WORK_DIR}/resukisu_display.txt"
  printf '%s\n' "${KSU_VERSION}" > "${WORK_DIR}/ksu_version.txt"
  printf '%s\n' "${KSU_UAPI_VERSION}" > "${WORK_DIR}/ksu_uapi_version.txt"
  printf '%s\n' "${ROM_ID}" > "${WORK_DIR}/rom_id.txt"
  cd "${BUILD_ROOT}"
  endlog
}

# ---------------------------------------------------------------------------
# 3) Toolchain (prefer this tree / XPENG_BUILD_ROOT, else download)
# ---------------------------------------------------------------------------
resolve_tool() {
  local name="$1"
  shift
  local cand
  for cand in "$@"; do
    if [[ -n "${cand}" && -x "${cand}" ]]; then
      printf '%s\n' "${cand}"
      return 0
    fi
  done
  die "MISSING tool: ${name}"
}

setup_toolchain() {
  log "Setup toolchain (${CLANG_VERSION})"

  local clang_bin ld_lld llvm_ar llvm_nm make_bin gcc_prefix dtc_bin ufdt_bin

  if [[ -x "${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/clang" ]]; then
    info "Using toolchains at ${XPENG_BUILD_ROOT}"
    clang_bin="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/clang"
    ld_lld="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/ld.lld"
    llvm_ar="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/llvm-ar"
    llvm_nm="${XPENG_BUILD_ROOT}/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin/llvm-nm"
    make_bin="${XPENG_BUILD_ROOT}/prebuilts/build-tools/linux-x86/bin/make"
    gcc_prefix="${XPENG_BUILD_ROOT}/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
    dtc_bin="${XPENG_BUILD_ROOT}/prebuilts/misc/linux-x86/dtc/dtc"
    ufdt_bin="${XPENG_BUILD_ROOT}/prebuilts/misc/linux-x86/libufdt/ufdt_apply_overlay"
  else
    info "Preparing CI toolchains under ${TOOLCHAIN_DIR}"
    local clang_dir="${TOOLCHAIN_DIR}/clang/host/linux-x86"
    if [[ ! -x "${clang_dir}/${CLANG_VERSION}/bin/clang" ]]; then
      mkdir -p "${clang_dir}"
      if [[ ! -d "${clang_dir}/.git" ]]; then
        git clone --filter=blob:none --no-checkout "${CLANG_GIT_URL}" "${clang_dir}" \
          || git clone --filter=blob:none --no-checkout "${CLANG_GIT_FALLBACK}" "${clang_dir}"
      fi
      (
        cd "${clang_dir}"
        git sparse-checkout init --cone
        git sparse-checkout set "${CLANG_VERSION}"
        git checkout 225d2925 2>/dev/null || git checkout main || git checkout master
      )
    fi
    [[ -x "${clang_dir}/${CLANG_VERSION}/bin/clang" ]] || die "clang not found after clone"

    local gcc_dir="${TOOLCHAIN_DIR}/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"
    if [[ ! -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]]; then
      mkdir -p "$(dirname "${gcc_dir}")"
      # Drop empty/broken clones (AOSP main tip has no binaries).
      if [[ -d "${gcc_dir}" && ! -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]]; then
        info "Removing incomplete gcc tree at ${gcc_dir}"
        rm -rf "${gcc_dir}"
      fi
      if [[ ! -d "${gcc_dir}/.git" ]]; then
        info "Cloning gcc 4.9 from ${GCC_GIT_URL} (${GCC_GIT_BRANCH})"
        git clone --depth=1 --branch "${GCC_GIT_BRANCH}" "${GCC_GIT_URL}" "${gcc_dir}" \
          || git clone --depth=1 --branch "${GCC_GIT_FALLBACK_BRANCH}" \
               "${GCC_GIT_FALLBACK}" "${gcc_dir}"
      fi
    fi
    [[ -x "${gcc_dir}/bin/aarch64-linux-android-gcc" ]] || die "gcc 4.9 not found after clone"

    clang_bin="${clang_dir}/${CLANG_VERSION}/bin/clang"
    ld_lld="${clang_dir}/${CLANG_VERSION}/bin/ld.lld"
    llvm_ar="${clang_dir}/${CLANG_VERSION}/bin/llvm-ar"
    llvm_nm="${clang_dir}/${CLANG_VERSION}/bin/llvm-nm"
    make_bin="$(resolve_tool make \
      "${HOST_BIN_DIR}/make" \
      "$(command -v make || true)")"
    gcc_prefix="${gcc_dir}/bin/aarch64-linux-android-"
    dtc_bin="$(resolve_tool dtc \
      "${HOST_BIN_DIR}/dtc" \
      "$(command -v dtc || true)")"
    ufdt_bin="$(resolve_tool ufdt_apply_overlay \
      "${HOST_BIN_DIR}/ufdt_apply_overlay")"
  fi

  # Prefer bundled host-bin when present (portable CI binaries)
  [[ -x "${HOST_BIN_DIR}/make" ]] && make_bin="${HOST_BIN_DIR}/make"
  [[ -x "${HOST_BIN_DIR}/dtc" ]] && dtc_bin="${HOST_BIN_DIR}/dtc"
  [[ -x "${HOST_BIN_DIR}/ufdt_apply_overlay" ]] && ufdt_bin="${HOST_BIN_DIR}/ufdt_apply_overlay"

  for t in "${clang_bin}" "${ld_lld}" "${llvm_ar}" "${llvm_nm}" "${make_bin}" \
           "${gcc_prefix}gcc" "${dtc_bin}" "${ufdt_bin}"; do
    [[ -x "${t}" ]] || die "MISSING: ${t}"
  done

  CLANG="${clang_bin}"
  LD_LLD="${ld_lld}"
  LLVM_AR="${llvm_ar}"
  LLVM_NM="${llvm_nm}"
  MAKE="${make_bin}"
  AARCH64_PREFIX="${gcc_prefix}"
  DTC_EXT="${dtc_bin}"
  UFDT_EXT="${ufdt_bin}"
  export CLANG LD_LLD LLVM_AR LLVM_NM MAKE AARCH64_PREFIX DTC_EXT UFDT_EXT
  export PATH="${HOST_BIN_DIR}:$(dirname "${CLANG}"):${PATH}"
  export TARGET_BUILD_VARIANT TARGET_PRODUCT
  # generate_defconfig invokes `${MAKE_PATH}make`
  export MAKE_PATH="${HOST_BIN_DIR}/"

  info "clang: $(${CLANG} --version | head -1)"
  info "make: ${MAKE}"
  info "NFC: ${ENABLE_NFC}"
  endlog
}

# ---------------------------------------------------------------------------
# 4) Build kernel Image (Motorola GKI generate_defconfig flow)
# ---------------------------------------------------------------------------
apply_nfc_overlay() {
  local cfg="${KERNEL_DIR}/arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config"
  [[ -f "${cfg}" ]] || die "missing ${cfg}"

  if git -C "${KERNEL_DIR}" show HEAD:"arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" >/dev/null 2>&1; then
    git -C "${KERNEL_DIR}" checkout HEAD -- "arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config"
  fi

  if [[ "${ENABLE_NFC}" == "true" ]]; then
    info "Enabling CONFIG_NFC_QTI_I2C=m for ${DEVICE_TITLE}"
    if grep -q '^# CONFIG_NFC_QTI_I2C is not set$' "${cfg}"; then
      sed -i 's/^# CONFIG_NFC_QTI_I2C is not set$/CONFIG_NFC_QTI_I2C=m/' "${cfg}"
    elif grep -q '^CONFIG_NFC_QTI_I2C=' "${cfg}"; then
      sed -i 's/^CONFIG_NFC_QTI_I2C=.*/CONFIG_NFC_QTI_I2C=m/' "${cfg}"
    else
      printf '\nCONFIG_NFC_QTI_I2C=m\n' >> "${cfg}"
    fi
  else
    info "Keeping NFC disabled (default) for ${DEVICE_TITLE}"
    if grep -q '^CONFIG_NFC_QTI_I2C=' "${cfg}"; then
      sed -i 's/^CONFIG_NFC_QTI_I2C=.*/# CONFIG_NFC_QTI_I2C is not set/' "${cfg}"
    fi
  fi
  grep -n 'NFC_QTI_I2C' "${cfg}" || true
}

restore_nfc_config() {
  if git -C "${KERNEL_DIR}" show HEAD:"arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" >/dev/null 2>&1; then
    git -C "${KERNEL_DIR}" checkout HEAD -- \
      "arch/arm64/configs/vendor/ext_config/moto-lahaina-xpeng.config" 2>/dev/null || true
  fi
}

build_kernel() {
  log "Build kernel Image (${VARIANT}, NFC=${ENABLE_NFC})"
  apply_nfc_overlay
  trap restore_nfc_config EXIT

  export ARCH=arm64
  export KBUILD_BUILD_USER=github-actions
  export KBUILD_BUILD_HOST=resukisu-ci
  export TARGET_BUILD_VARIANT TARGET_PRODUCT

  local hostcflags hostldflags
  hostcflags="-I${KERNEL_DIR}/include/uapi -I/usr/include -I/usr/include/x86_64-linux-gnu -I${KERNEL_DIR}/include -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
  hostldflags="-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"

  local common_make=(
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
  )

  info "generate_defconfig vendor/lahaina-qgki_defconfig"
  rm -rf "${OUT_DIR}"
  mkdir -p "${OUT_DIR}"

  pushd "${KERNEL_DIR}" >/dev/null

  # envsetup uses `ls ... 2>/dev/null` which may return non-zero
  set +e
  # shellcheck disable=SC1091
  source "${KERNEL_DIR}/scripts/gki/envsetup.sh" lahaina
  set -e

  MAKE_PATH= ARCH=arm64 \
    CROSS_COMPILE="${AARCH64_PREFIX}" \
    REAL_CC="${CLANG}" CLANG_TRIPLE=aarch64-linux-gnu- \
    AR="${LLVM_AR}" LLVM_NM="${LLVM_NM}" LD="${LD_LLD}" NM="${LLVM_NM}" \
    KERN_OUT="${OUT_DIR}" \
    DTC_EXT="${DTC_EXT}" DTC_OVERLAY_TEST_EXT="${UFDT_EXT}" \
    CONFIG_BUILD_ARM64_DT_OVERLAY=y \
    HOSTCC="${CLANG}" HOSTAR="${LLVM_AR}" HOSTLD="${LD_LLD}" \
    TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT}" \
    TARGET_PRODUCT="${TARGET_PRODUCT}" \
    "${KERNEL_DIR}/scripts/gki/generate_defconfig.sh" vendor/lahaina-qgki_defconfig

  info "defconfig"
  "${MAKE}" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    vendor/lahaina-qgki_defconfig

  # Enforce NFC choice on final .config as well
  if [[ "${ENABLE_NFC}" == "true" ]]; then
    "${KERNEL_DIR}/scripts/config" --file "${OUT_DIR}/.config" --module NFC_QTI_I2C || true
  else
    "${KERNEL_DIR}/scripts/config" --file "${OUT_DIR}/.config" --disable NFC_QTI_I2C || true
  fi
  "${MAKE}" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    olddefconfig

  info "headers_install"
  "${MAKE}" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}" \
    headers_install

  info "Compiling Image (-j${JOBS})"
  "${MAKE}" -j"${JOBS}" -C "${KERNEL_DIR}" O="${OUT_DIR}" \
    "${common_make[@]}" \
    HOSTCFLAGS="${hostcflags}" HOSTLDFLAGS="${hostldflags}"

  popd >/dev/null

  local image="${OUT_DIR}/arch/arm64/boot/Image"
  [[ -f "${image}" ]] || die "Build failed: ${image} not found"
  info "Image size: $(du -h "${image}" | awk '{print $1}')"
  if [[ -f "${OUT_DIR}/.config" ]]; then
    grep -E 'CONFIG_NFC_QTI_I2C' "${OUT_DIR}/.config" || true
  fi
  cp -f "${image}" "${WORK_DIR}/release/Image"

  restore_nfc_config
  git -C "${KERNEL_DIR}" checkout HEAD -- \
    arch/arm64/configs/vendor/lahaina-qgki_defconfig 2>/dev/null || true
  trap - EXIT
  endlog
}

# ---------------------------------------------------------------------------
# Ensure boot_oem.img (local copy, ~/下载, or Release asset download)
# ---------------------------------------------------------------------------
ensure_boot_oem() {
  log "Ensure boot_oem.img"
  if [[ -f "${BOOT_OEM_IMG}" ]]; then
    info "Using existing ${BOOT_OEM_IMG} ($(du -h "${BOOT_OEM_IMG}" | awk '{print $1}'))"
    endlog
    return 0
  fi

  mkdir -p "$(dirname "${BOOT_OEM_IMG}")"

  if [[ -f "${HOME}/下载/boot_oem.img" ]]; then
    info "Copying ${HOME}/下载/boot_oem.img"
    cp -f "${HOME}/下载/boot_oem.img" "${BOOT_OEM_IMG}"
    endlog
    return 0
  fi

  local url="https://github.com/${BOOT_OEM_RELEASE_REPO}/releases/download/${BOOT_OEM_RELEASE_TAG}/${BOOT_OEM_ASSET_NAME}"
  if [[ -n "${GITHUB_PROXY:-}" ]]; then
    url="${GITHUB_PROXY%/}/${url}"
  fi
  info "Downloading ${url}"
  curl_get -o "${BOOT_OEM_IMG}.partial" "${url}"
  mv -f "${BOOT_OEM_IMG}.partial" "${BOOT_OEM_IMG}"
  [[ -f "${BOOT_OEM_IMG}" ]] || die "failed to download boot_oem.img"
  info "Downloaded ${BOOT_OEM_IMG} ($(du -h "${BOOT_OEM_IMG}" | awk '{print $1}'))"
  endlog
}

# ---------------------------------------------------------------------------
# 5-7) magiskboot unpack boot_oem.img -> replace kernel -> repack
# ---------------------------------------------------------------------------
setup_magiskboot() {
  log "Setup magiskboot"
  local magisk_dir="${TOOLCHAIN_DIR}/magisk"
  mkdir -p "${magisk_dir}"
  if [[ ! -x "${magisk_dir}/magiskboot" ]]; then
    for cand in \
      "${HOME}/下载/boot_unpack/tools/magiskboot" \
      "${HOME}/android/android_kernel_motorola_sm7325/.ci-toolchain/magisk/magiskboot"; do
      if [[ -x "${cand}" ]]; then
        cp -f "${cand}" "${magisk_dir}/magiskboot"
        chmod +x "${magisk_dir}/magiskboot"
        break
      fi
    done
  fi
  if [[ ! -x "${magisk_dir}/magiskboot" ]]; then
    local tag apk
    local magisk_api="https://api.github.com/repos/topjohnwu/Magisk/releases/latest"
    local magisk_base="https://github.com/topjohnwu/Magisk/releases/download"
    if [[ -n "${GITHUB_PROXY:-}" ]]; then
      magisk_api="${GITHUB_PROXY%/}/${magisk_api}"
      magisk_base="${GITHUB_PROXY%/}/${magisk_base}"
    fi
    tag="$(curl_get -fsS "${magisk_api}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')"
    apk="${magisk_dir}/Magisk-${tag}.apk"
    curl_get -o "${apk}" "${magisk_base}/${tag}/Magisk-${tag}.apk"
    python3 - <<PY
import zipfile
apk="${apk}"
out="${magisk_dir}/magiskboot"
with zipfile.ZipFile(apk) as z:
    for name in ("lib/x86_64/libmagiskboot.so", "lib/x86/libmagiskboot.so"):
        if name in z.namelist():
            with z.open(name) as src, open(out, "wb") as dst:
                dst.write(src.read())
            break
    else:
        raise SystemExit("libmagiskboot.so not found in Magisk apk")
PY
    chmod +x "${magisk_dir}/magiskboot"
  fi
  export MAGISKBOOT="${magisk_dir}/magiskboot"
  info "magiskboot: ${MAGISKBOOT}"
  endlog
}

repack_boot() {
  log "Repack boot.img with custom kernel"
  [[ -f "${BOOT_OEM_IMG}" ]] || die "boot_oem.img not found: ${BOOT_OEM_IMG}"

  local unpack_dir="${WORK_DIR}/boot/unpack"
  rm -rf "${unpack_dir}"
  mkdir -p "${unpack_dir}"
  cp -f "${BOOT_OEM_IMG}" "${unpack_dir}/boot.img"
  pushd "${unpack_dir}" >/dev/null

  "${MAGISKBOOT}" unpack boot.img
  [[ -f kernel ]] || die "magiskboot did not produce 'kernel'"

  cp -f "${WORK_DIR}/release/Image" kernel
  "${MAGISKBOOT}" repack boot.img new-boot.img
  [[ -f new-boot.img ]] || die "magiskboot repack failed"

  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt")}"
  local safe_ver
  safe_ver="$(echo "${RESUKISU_VERSION}" | tr '/:' '--')"

  cp -f new-boot.img "${WORK_DIR}/release/boot_ksu.img"
  cp -f new-boot.img "${WORK_DIR}/release/boot.img"

  local out_name="boot_ksu-${VARIANT_SLUG}-ReSukiSU-${safe_ver}-${ROM_ID}.img"
  cp -f new-boot.img "${WORK_DIR}/release/${out_name}"

  popd >/dev/null

  local build_id
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    build_id="r${GITHUB_RUN_NUMBER}"
  else
    build_id="$(date -u +%Y%m%d%H%M%S)"
  fi

  case "${VARIANT}" in
    edge-s30) RELEASE_TAG="MMI-${ROM_ID}-ReSukiSU-EdgeS30-${build_id}" ;;
    g200)     RELEASE_TAG="MMI-${ROM_ID}-ReSukiSU-G200-${build_id}" ;;
  esac

  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  RELEASE_NAME="${RELEASE_TITLE}"
  BOOT_ARTIFACT="${WORK_DIR}/release/boot_ksu.img"
  export RELEASE_TAG RELEASE_NAME BOOT_ARTIFACT VARIANT_SLUG DEVICE_TITLE

  gh_env RELEASE_TAG "${RELEASE_TAG}"
  gh_env RELEASE_NAME "${RELEASE_NAME}"
  gh_env BOOT_ARTIFACT "${BOOT_ARTIFACT}"
  gh_env VARIANT_SLUG "${VARIANT_SLUG}"
  gh_env DEVICE_TITLE "${DEVICE_TITLE}"
  gh_env ROM_ID "${ROM_ID}"
  gh_env WORK_DIR "${WORK_DIR}"

  info "Output: ${BOOT_ARTIFACT}"
  info "Release tag: ${RELEASE_TAG}"
  endlog
}

pack_anykernel3() {
  log "Pack AnyKernel3 zip (kernel + vendor WiFi kos if present)"
  local pack_script
  pack_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pack_anykernel3.sh"
  [[ -f "${pack_script}" ]] || die "missing ${pack_script}"
  BUILD_ROOT="${BUILD_ROOT}" WORK_DIR="${WORK_DIR}" DEVICE="${DEVICE}" \
    DEVICE_TITLE="${DEVICE_TITLE}" \
    VARIANT_SLUG="${VARIANT_SLUG}" \
    RESUKISU_VERSION="${RESUKISU_VERSION:-}" \
    RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-}" \
    ROM_ID="${ROM_ID}" \
    WLAN_OUT_DIR="${WLAN_OUT_DIR:-${WORK_DIR}/wlan-kos}" \
    GITHUB_PROXY="${GITHUB_PROXY:-}" \
    KERNEL_IMAGE="${WORK_DIR}/release/Image" \
    bash "${pack_script}"
  endlog
}

write_release_notes() {
  RESUKISU_VERSION="${RESUKISU_VERSION:-$(cat "${WORK_DIR}/resukisu_version.txt")}"
  RESUKISU_DISPLAY="${RESUKISU_DISPLAY:-$(cat "${WORK_DIR}/resukisu_display.txt" 2>/dev/null || echo "${RESUKISU_VERSION}@ReSukiSU")}"
  AK3_COMMIT="${AK3_COMMIT:-$(cat "${WORK_DIR}/ak3_commit.txt" 2>/dev/null || echo unknown)}"
  local nfc_note="disabled (default)"
  [[ "${ENABLE_NFC}" == "true" ]] && nfc_note="enabled (CONFIG_NFC_QTI_I2C=m)"

  cat > "${WORK_DIR}/release/RELEASE_NOTES.md" <<EOF
## HOW TO USE

\`\`\`
# Press the volume down and power buttons to enter FASTBOOT mode, then enter the command to enter Fastboot mode.
# 按音量下和开机键进入 FASTBOOT 模式，输入命令，进入 Fastbootd
fastboot reboot fastboot

# Flash boot_ksu.img
# 刷写 boot_ksu.img
fastboot flash boot boot_ksu.img

# If the device fails to boot after flashing, you will need to format the Data.
# 如果刷写后无法开机，则需要格式化 Data
fastboot -w
\`\`\`

### AnyKernel3 (any ROM)

Sideload or flash \`AnyKernel3-*.zip\` in a custom recovery, or use a kernel flasher app.
If the zip contains WiFi kos, they are pushed to \`/vendor/lib/modules/\` (\`do.modules=1\`). No KernelSU WiFi module install is needed.

## Notes
- Device: ${DEVICE_TITLE}
- MYUI: 4.0
- Android 12
- ROM: ${ROM_ID}
- ReSukiSU: ${RESUKISU_DISPLAY}
- NFC: ${nfc_note}
- AnyKernel3: [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) \`${AK3_COMMIT}\` (\`do.modules=1\`)

## Assets
- \`boot_ksu.img\` — OEM boot.img with replaced ReSukiSU kernel
- \`Image\` — raw ARM64 kernel Image
- \`AnyKernel3-*.zip\` — flashable zip (kernel + vendor WiFi kos when present; no KernelSU WiFi module)

> Built automatically from \`kernel_motorola_xpeng_build\` (\`S3RXC32.33-8-29-ReSukiSU\`) using kernel sources from [android_kernel_motorola_xpeng](https://github.com/LuoJuly/android_kernel_motorola_xpeng) with the latest ReSukiSU submodule and latest AnyKernel3 upstream.
EOF
  gh_env RELEASE_NOTES "${WORK_DIR}/release/RELEASE_NOTES.md"
  info "Release notes written"
}

main() {
  info "Variant=${VARIANT} Device=${DEVICE_TITLE} NFC=${ENABLE_NFC}"
  info "BUILD_ROOT=${BUILD_ROOT}"
  fetch_kernel
  update_resukisu
  setup_toolchain
  if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    build_kernel
  else
    [[ -f "${WORK_DIR}/release/Image" || -f "${OUT_DIR}/arch/arm64/boot/Image" ]] \
      || die "SKIP_BUILD=true but Image not found"
    mkdir -p "${WORK_DIR}/release"
    if [[ ! -f "${WORK_DIR}/release/Image" ]]; then
      cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${WORK_DIR}/release/Image"
    fi
    info "Skipping kernel build; using existing Image"
  fi
  ensure_boot_oem
  setup_magiskboot
  repack_boot
  pack_anykernel3
  if [[ -n "${AK3_COMMIT:-}" ]]; then
    printf '%s\n' "${AK3_COMMIT}" > "${WORK_DIR}/ak3_commit.txt"
  fi
  write_release_notes
  info "Done. Artifacts in ${WORK_DIR}/release/"
  ls -lh "${WORK_DIR}/release/"
}

main "$@"
