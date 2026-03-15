#!/usr/bin/env bash
# build-iso.sh — Embed kickstart.ks into an AlmaLinux ISO
# Produces a custom ISO that boots directly into the unattended install.
#
# Usage: bash build-iso.sh <input-iso> [output-iso]
# Example: bash build-iso.sh AlmaLinux-10.1-x86_64-dvd.iso
#
# Requires: lorax (provides mkksiso)
#   sudo dnf install -y lorax

set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_ISO="${1:-}"
OUTPUT_ISO="${2:-al10-daily-driver.iso}"
KS="$SCRIPT_DIR/kickstart.ks"

# ── Checks ────────────────────────────────────────────────────────────────────
[[ -n "$INPUT_ISO" ]] || { echo "Usage: $0 <input-iso> [output-iso]" >&2; exit 1; }
[[ -f "$INPUT_ISO" ]] || { echo "ERROR: input ISO not found: $INPUT_ISO" >&2; exit 1; }
[[ -f "$KS" ]]        || { echo "ERROR: kickstart.ks not found: $KS" >&2; exit 1; }
[[ -f "$OUTPUT_ISO" ]] && { echo "==> Removing existing $OUTPUT_ISO"; rm -f "$OUTPUT_ISO"; }

command -v mkksiso >/dev/null 2>&1 || {
    echo "ERROR: mkksiso not found. Install it with:"
    echo "  sudo dnf install -y lorax"
    exit 1
}

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Embedding kickstart into ISO..."
echo "    Input:  $INPUT_ISO"
echo "    Output: $OUTPUT_ISO"

mkksiso "$KS" "$INPUT_ISO" "$OUTPUT_ISO"

echo ""
echo "==> Done: $OUTPUT_ISO"
echo ""
echo "Write to USB with:"
echo "  sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress"
echo "  sudo eject /dev/sdX"
