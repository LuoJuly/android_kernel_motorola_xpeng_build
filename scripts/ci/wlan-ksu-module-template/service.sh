#!/system/bin/sh
# Vendor early-init loads qca_cld3_*.ko BEFORE KSU overlay. After overlay is up,
# ensure CRC/vermagic-matched wlan is loaded and kick Wi-Fi.
# Note: toybox/modinfo on this device often returns empty for .ko — do NOT wait on it.
MODDIR=${0%/*}
KO_VENDOR=/vendor/lib/modules/qca_cld3_wlan.ko
KO_MOD="$MODDIR/system/vendor/lib/modules/qca_cld3_wlan.ko"
LOG=/data/local/tmp/wlan_crc_match_302.log

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

log "service.sh start ker=$(uname -r)"

# Wait briefly for overlay path / module file (not modinfo)
i=0
while [ "$i" -lt 20 ]; do
	if [ -f "$KO_VENDOR" ] || [ -f "$KO_MOD" ]; then
		# Prefer strings check for 5.4.302 marker once file exists
		if strings "$KO_VENDOR" 2>/dev/null | grep -q '5\.4\.302-moto'; then
			break
		fi
		if strings "$KO_MOD" 2>/dev/null | grep -q '5\.4\.302-moto'; then
			break
		fi
	fi
	sleep 1
	i=$((i + 1))
done
log "file wait done i=$i vendor=$([ -f "$KO_VENDOR" ] && echo y || echo n) mod=$([ -f "$KO_MOD" ] && echo y || echo n)"

pick_ko() {
	if [ -f "$KO_VENDOR" ] && strings "$KO_VENDOR" 2>/dev/null | grep -q '5\.4\.302-moto'; then
		echo "$KO_VENDOR"
		return
	fi
	if [ -f "$KO_MOD" ]; then
		echo "$KO_MOD"
		return
	fi
	echo "$KO_VENDOR"
}

KO=$(pick_ko)
log "using KO=$KO"

if lsmod | grep -q '^wlan '; then
	log "wlan already loaded"
else
	log "insmod $KO"
	insmod "$KO" >>"$LOG" 2>&1
	log "insmod exit=$?"
fi

# Kick Wi-Fi a few times (framework may have failed before driver was ready)
n=0
while [ "$n" -lt 5 ]; do
	cmd wifi set-wifi-enabled enabled >>"$LOG" 2>&1 || svc wifi enable >>"$LOG" 2>&1
	sleep 2
	st=$(getprop wlan.driver.status 2>/dev/null || true)
	log "wifi kick n=$n driver.status=$st"
	case "$st" in
		ok|OK) break ;;
	esac
	n=$((n + 1))
done

log "service.sh done lsmod_wlan=$(lsmod | grep '^wlan ' | awk '{print $1,$2}' | tr '\n' ' ')"
