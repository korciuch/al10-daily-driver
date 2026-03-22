#!/usr/bin/env bash
# collect-diag.sh — Post-setup diagnostic collector for al10-daily-driver
# Usage: sudo bash collect-diag.sh [output-dir]
# Default output: /run/media/admin/ERROR-LOG-D/diag-<timestamp>/

set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"

OUT="${1:-/run/media/admin/ERROR-LOG-D}/diag-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

log()  { echo "==> $*"; }
cap()  {
    local label="$1"; shift
    log "$label"
    # Run the command; tolerate failures so one bad command doesn't abort the whole script
    "$@" > "$OUT/$label" 2>&1 || echo "[command exited $?]" >> "$OUT/$label"
}
capj() {
    # journalctl variant — always succeeds
    local label="$1"; shift
    log "$label"
    journalctl "$@" --no-pager 2>&1 > "$OUT/$label" || true
}

# ── System identity ───────────────────────────────────────────────────────────
cap  "00-uname.txt"            uname -a
cap  "00-os-release.txt"       cat /etc/os-release
cap  "00-cmdline.txt"          cat /proc/cmdline
cap  "00-uptime.txt"           uptime

# ── Boot journal (errors + warnings first, then full) ─────────────────────────
capj "01-journal-errors.txt"   -b 0 -p err..emerg
capj "02-journal-full.txt"     -b 0

# ── Failed units ──────────────────────────────────────────────────────────────
cap  "03-failed-units.txt"     systemctl list-units --state=failed --no-legend

# ── dmesg ─────────────────────────────────────────────────────────────────────
cap  "04-dmesg.txt"            dmesg -T

# ── Kernel modules ────────────────────────────────────────────────────────────
cap  "05-lsmod.txt"            lsmod
cap  "05-dkms-status.txt"      dkms status
cap  "05-modules-updates.txt"  ls -la /lib/modules/"$(uname -r)"/updates/ 2>/dev/null || echo "no updates dir"

# ── Specific driver status ────────────────────────────────────────────────────
for mod in xe i915 iwlwifi iwlmld r8152 snd_sof_pci_intel_mtl \
           intel_ipu6 intel_ipu6_isys intel_ipu6_psys ov02c10; do
    modinfo "$mod" 2>&1 | head -5 >> "$OUT/06-modinfo-summary.txt"
    echo "---" >> "$OUT/06-modinfo-summary.txt"
done

# ── PCI devices with bound drivers ────────────────────────────────────────────
cap  "07-lspci-k.txt"          lspci -nnk
cap  "07-lspci-v.txt"          lspci -nnv

# ── USB devices ───────────────────────────────────────────────────────────────
cap  "08-lsusb.txt"            lsusb
cap  "08-lsusb-v.txt"          lsusb -v 2>/dev/null || true

# ── Network ───────────────────────────────────────────────────────────────────
cap  "09-ip-link.txt"          ip link show
cap  "09-ip-addr.txt"          ip addr show
cap  "09-nmcli-general.txt"    nmcli general status
cap  "09-nmcli-dev.txt"        nmcli device status
cap  "09-nmcli-con.txt"        nmcli connection show
capj "09-journal-nm.txt"       -b 0 -u NetworkManager
cap  "09-nm-conf.txt"          bash -c 'ls -la /etc/NetworkManager/conf.d/ /var/lib/NetworkManager/ 2>/dev/null && cat /etc/NetworkManager/conf.d/*.conf 2>/dev/null || true'

# ── GPU / display / hardware accel ────────────────────────────────────────────
cap  "10-drm-devices.txt"      ls -la /dev/dri/ 2>/dev/null || echo "no /dev/dri"
cap  "10-vainfo.txt"           bash -c 'vainfo 2>&1 || echo "vainfo not available"'
capj "10-journal-drm.txt"      -b 0 -k SYSLOG_IDENTIFIER=kernel -g "drm|xe|i915|GuC|HuC|firmware"
cap  "10-display-env.txt"      bash -c 'echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY" 2>/dev/null || true; loginctl list-sessions 2>/dev/null || true'

# ── Camera ────────────────────────────────────────────────────────────────────
cap  "11-video-devices.txt"    bash -c 'ls /dev/video* /dev/media* 2>/dev/null || echo "no video/media devices"'
capj "11-journal-ipu.txt"      -b 0 -k SYSLOG_IDENTIFIER=kernel -g "ipu6|ov02c10|ivsc|vsc|ipu_bridge|OVTI"

# ── Audio ─────────────────────────────────────────────────────────────────────
cap  "12-aplay.txt"            aplay -l 2>/dev/null || echo "aplay not available / no devices"
capj "12-journal-sof.txt"      -b 0 -k SYSLOG_IDENTIFIER=kernel -g "sof|SOF|HDA"
cap  "12-sof-firmware.txt"     ls -la /lib/firmware/intel/sof-ipc4/ 2>/dev/null || echo "no sof-ipc4 firmware"

# ── Firmware inventory ────────────────────────────────────────────────────────
cap  "13-firmware-ipu.txt"     ls -la /lib/firmware/intel/ipu/ 2>/dev/null || echo "missing"
cap  "13-firmware-vsc.txt"     ls -la /lib/firmware/intel/vsc/ 2>/dev/null || echo "missing"
cap  "13-firmware-iwl.txt"     ls /lib/firmware/iwlwifi-*.ucode 2>/dev/null || echo "missing"

# ── SELinux ───────────────────────────────────────────────────────────────────
cap  "14-sestatus.txt"         sestatus
cap  "14-avc-denials.txt"      ausearch -m avc -ts boot 2>/dev/null || echo "ausearch unavailable or no denials"

# ── DKMS build log ────────────────────────────────────────────────────────────
DKMS_LOG_DIR="/var/lib/dkms/ipu6-drivers"
if [[ -d "$DKMS_LOG_DIR" ]]; then
    cp -r "$DKMS_LOG_DIR" "$OUT/15-dkms-ipu6-build/" 2>/dev/null || true
else
    echo "no ipu6-drivers dkms tree" > "$OUT/15-dkms-ipu6-build.txt"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo " Diagnostics saved to: $OUT"
echo " Files:"
ls "$OUT/"
echo "======================================================"
