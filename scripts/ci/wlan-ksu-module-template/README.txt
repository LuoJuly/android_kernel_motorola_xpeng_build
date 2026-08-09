wlan_crc_match_302 — CRC-matched qcacld for kernel 5.4.302

Overlays:
  /vendor/lib/modules/qca_cld3_wlan.ko
  /vendor/lib/modules/qca_cld3_qca6750.ko
  /vendor/lib/modules/qca_cld3_qca6390.ko

Why service.sh:
  Vendor loads qca_cld3_*.ko in early-init BEFORE KernelSU/hybrid_mount
  overlay is applied. Overlay alone is not enough; service.sh waits for the
  matched .ko then insmod + enables Wi-Fi.

Install order:
  1) Flash boot_ksu.img / AnyKernel3 (MODVERSIONS=y, kernel 5.4.302)
  2) If using standalone zip: install via KernelSU Manager
  3) Reboot
  4) If Wi-Fi still off, toggle Wi-Fi once in Settings

When flashed via AnyKernel3, the Magisk/KSU module zip is also extracted to
/sdcard/Download/ and (when possible) installed under /data/adb/modules/.
