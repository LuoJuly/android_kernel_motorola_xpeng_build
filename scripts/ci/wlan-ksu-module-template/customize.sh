#!/system/bin/sh
# Magisk/KernelSU module: overlay matched qcacld modules onto /vendor/lib/modules
SKIPUNZIP=0
set_perm_recursive "$MODPATH/system/vendor/lib/modules" 0 0 0755 0644
ui_print "- Installing CRC-matched qca_cld3_*.ko for 5.4.210"
ui_print "- Target: /vendor/lib/modules/qca_cld3_{wlan,qca6750,qca6390}.ko"
ui_print "- service.sh will late-insmod after overlay (early-init races overlay)"
ui_print "- Reboot after install"
