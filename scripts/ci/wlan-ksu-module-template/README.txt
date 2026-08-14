wlan_crc_match_210 — CRC-matched qcacld for kernel 5.4.210

Overlays:
  /vendor/lib/modules/qca_cld3_wlan.ko
  /vendor/lib/modules/qca_cld3_qca6750.ko
  /vendor/lib/modules/qca_cld3_qca6390.ko

Why service.sh:
  Vendor loads qca_cld3_*.ko in early-init BEFORE KernelSU/hybrid_mount
  overlay is applied. Overlay alone is not enough; service.sh waits for the
  matched .ko then insmod + enables Wi-Fi.

Install order (fastboot boot.img only — AnyKernel3 does not need this zip):
  1) Flash boot_ksu.img (MODVERSIONS=y, kernel 5.4.210)
  2) Install this zip via KernelSU Manager
  3) Reboot
  4) If Wi-Fi still off, toggle Wi-Fi once in Settings

AnyKernel3 already pushes qca_cld3_*.ko to /vendor/lib/modules/ (do.modules=1).
Do not install this KSU module after flashing AnyKernel3.
