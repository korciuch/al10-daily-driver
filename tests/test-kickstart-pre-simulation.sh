#!/usr/bin/env bash
# Simulates the kickstart %pre block locally.
# Verifies that disk-include and part-include are generated correctly.
# Does NOT modify the system — output goes to /tmp/ks-sim/.

set -euo pipefail
SIMDIR="/tmp/ks-sim"
rm -rf "$SIMDIR" && mkdir -p "$SIMDIR"

# ── Replicate %pre disk detection ─────────────────────────────────────────────
DISK=$(lsblk -d -n -o NAME,RM,TYPE 2>/dev/null | awk '$2==0 && $3=="disk"{print $1}' | head -1)
DISK_MB=0
[ -n "$DISK" ] && DISK_MB=$(lsblk -b -d -n -o SIZE /dev/$DISK 2>/dev/null | awk '{print int($1/1024/1024)}')
[ "$DISK_MB" -eq 0 ] && DISK_MB=40960

echo "Detected disk : $DISK"
echo "Disk size     : ${DISK_MB} MB ($(( DISK_MB / 1024 )) GB)"
echo ""

# ── Generate disk-include ──────────────────────────────────────────────────────
cat > "$SIMDIR/disk-include" <<DISKEOF
clearpart --all --initlabel --drives=${DISK}
bootloader --location=mbr --boot-drive=${DISK}
part /boot/efi --fstype=efi  --size=600  --asprimary --ondisk=${DISK}
part /boot     --fstype=xfs  --size=1024             --ondisk=${DISK}
part pv.01     --size=1      --grow      --encrypted --luks-version=luks2 --passphrase=testpass123 --ondisk=${DISK}
DISKEOF

# ── Generate part-include (LVM layout) ────────────────────────────────────────
if [ "$DISK_MB" -lt 102400 ]; then
    ROOT_MB=4096; HOME_MB=5120; SWAP_MB=4096; TMP_MB=1024
    VAR_MB=4096; VAR_TMP_MB=1024; VAR_LOG_MB=2048; VAR_LOG_AUDIT_MB=2048
    LAYOUT="test/VM (< 100 GB)"
else
    ROOT_MB=71680; HOME_MB=51200; SWAP_MB=16384; TMP_MB=5120
    VAR_MB=20480; VAR_TMP_MB=5120; VAR_LOG_MB=10240; VAR_LOG_AUDIT_MB=10240
    LAYOUT="production (>= 100 GB)"
fi

cat > "$SIMDIR/part-include" <<EOF
logvol /              --vgname=vg0 --fstype=xfs  --size=${ROOT_MB}          --name=root
logvol /home          --vgname=vg0 --fstype=xfs  --size=${HOME_MB}          --name=home
logvol /tmp           --vgname=vg0 --fstype=xfs  --size=${TMP_MB}           --name=tmp
logvol /var           --vgname=vg0 --fstype=xfs  --size=${VAR_MB}           --name=var
logvol /var/log       --vgname=vg0 --fstype=xfs  --size=${VAR_LOG_MB}       --name=var_log
logvol /var/log/audit --vgname=vg0 --fstype=xfs  --size=${VAR_LOG_AUDIT_MB} --name=var_log_audit
logvol /var/tmp       --vgname=vg0 --fstype=xfs  --size=${VAR_TMP_MB}       --name=var_tmp
logvol /var/vantage   --vgname=vg0 --fstype=xfs  --size=1 --grow            --name=var_vantage
logvol swap           --vgname=vg0 --fstype=swap  --size=${SWAP_MB}          --name=swap
EOF

# ── Print results ──────────────────────────────────────────────────────────────
echo "=== disk-include (what Anaconda receives for partitioning) ==="
cat "$SIMDIR/disk-include"

echo ""
echo "=== part-include (LVM layout — $LAYOUT) ==="
cat "$SIMDIR/part-include"

echo ""
echo "=== Partition accounting ==="
TOTAL_LVM=$(( ROOT_MB + HOME_MB + SWAP_MB + TMP_MB + VAR_MB + VAR_TMP_MB + VAR_LOG_MB + VAR_LOG_AUDIT_MB ))
LVM_OVERHEAD=600   # ~600 MB for LVM metadata, LUKS header, alignment
RESERVED=$(( 600 + 1024 ))
AVAILABLE=$(( DISK_MB - RESERVED ))
VANTAGE=$(( AVAILABLE - TOTAL_LVM - LVM_OVERHEAD ))

printf "  %-30s %8s MB\n"  "/boot/efi (EFI partition)"    "600"
printf "  %-30s %8s MB\n"  "/boot (XFS partition)"        "1024"
printf "  %-30s %8s\n"     "--- LVM (inside LUKS) ---"    ""
printf "  %-30s %8d MB\n"  "  /"                          "$ROOT_MB"
printf "  %-30s %8d MB\n"  "  /home"                      "$HOME_MB"
printf "  %-30s %8d MB\n"  "  /tmp"                       "$TMP_MB"
printf "  %-30s %8d MB\n"  "  /var"                       "$VAR_MB"
printf "  %-30s %8d MB\n"  "  /var/log"                   "$VAR_LOG_MB"
printf "  %-30s %8d MB\n"  "  /var/log/audit"             "$VAR_LOG_AUDIT_MB"
printf "  %-30s %8d MB\n"  "  /var/tmp"                   "$VAR_TMP_MB"
printf "  %-30s %8d MB\n"  "  /var/vantage (--grow)"      "$VANTAGE"
printf "  %-30s %8d MB\n"  "  swap"                       "$SWAP_MB"
printf "  %-30s %8s\n"     "  (~LVM overhead)"            "~${LVM_OVERHEAD} MB"
printf "  %s\n"            "----------------------------------------"
printf "  %-30s %8d MB  (%d GB)\n" "Total" "$DISK_MB" "$(( DISK_MB / 1024 ))"

echo ""
echo "=== Checks ==="
PASS=1

# All part commands must reference the detected disk
for keyword in "clearpart" "bootloader" "/boot/efi" "/boot " "pv.01"; do
    line=$(grep -i "$keyword" "$SIMDIR/disk-include" || true)
    if echo "$line" | grep -q "$DISK"; then
        echo "  OK  '$keyword' targets $DISK"
    else
        echo "  !! FAIL '$keyword' does NOT reference $DISK"
        PASS=0
    fi
done

# Vantage should have positive space
if [ "$VANTAGE" -gt 0 ]; then
    echo "  OK  /var/vantage has space to grow"
else
    echo "  !! FAIL disk too small for fixed LVM volumes"
    PASS=0
fi

echo ""
if [ "$PASS" -eq 1 ]; then
    echo "Level 1 PASSED — disk-include is correct for $DISK"
else
    echo "Level 1 FAILED — review output above"
    exit 1
fi
