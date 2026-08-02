#!/usr/bin/env bash
set -euo pipefail
TOP="$(cd "$(dirname "$0")" && pwd)"
cd "$TOP"

echo "======== 1/3 KERNEL ========"
"$TOP/build-kernel.sh"

echo "======== 2/3 WLAN ========"
"$TOP/build-wlan.sh"

echo "======== 3/3 INSTALL WLAN INTO MODULES TREE ========"
KOUT=$TOP/out/target/product/generic/obj/kernel/msm-5.4
# detect modules version dir
MODVER=$(ls -d "$KOUT/staging/lib/modules"/*/ 2>/dev/null | head -1)
if [ -z "${MODVER:-}" ]; then
  echo "No staging modules dir found" >&2
  exit 1
fi
EXTRA="${MODVER}extra"
mkdir -p "$EXTRA"
STRIP=$TOP/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-strip
for chip in wlan qca6750 qca6390; do
  src=$TOP/vendor/qcom/opensource/wlan/qcacld-3.0/.$chip/wlan.ko
  dst=$EXTRA/wlan-${chip}.ko
  cp -f "$src" "$dst"
  "$STRIP" --strip-debug "$dst" 2>/dev/null || "$STRIP" -g "$dst" || true
  ls -lh "$dst"
done

# also refresh convenient out/wlan-modules
mkdir -p "$TOP/out/wlan-modules"
cp -f "$EXTRA"/wlan-*.ko "$TOP/out/wlan-modules/"

echo "======== ALL DONE ========"
ls -lh "$KOUT/arch/arm64/boot/Image"
ls -lh "$TOP/out/wlan-modules"
echo "modules_dir=$MODVER"
find "$MODVER" -name '*.ko' | wc -l
