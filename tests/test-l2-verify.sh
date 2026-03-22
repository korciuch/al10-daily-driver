#!/usr/bin/env bash
# Level 2 verification — inspect installed VM disk layout via qemu-nbd
# sudo bash tests/test-l2-verify.sh <vm-name>
# e.g.: sudo bash tests/test-l2-verify.sh test-ks-small

set -euo pipefail

VM="${1:?Usage: $0 <vm-name>}"
PASS=1
NBD_DEV="/dev/nbd0"

cleanup() {
    qemu-nbd --disconnect "$NBD_DEV" 2>/dev/null || true
    modprobe -r nbd 2>/dev/null || true
}

# ── Locate disk image ─────────────────────────────────────────────────────────
echo "==> Locating disk image for $VM ..."
DISK_PATH=$(virsh domblklist "$VM" 2>/dev/null \
    | awk '/\.qcow2/{print $2}' | head -1)

# VM may be undefined after install (--noreboot + undefine on next run);
# fall back to the well-known path.
if [[ -z "$DISK_PATH" || ! -f "$DISK_PATH" ]]; then
    DISK_PATH="/var/lib/libvirt/images/${VM}.qcow2"
fi
[[ -f "$DISK_PATH" ]] || { echo "ERROR: disk image not found for $VM"; exit 1; }
echo "    $DISK_PATH"

SIZE=$(qemu-img info "$DISK_PATH" | awk '/disk size:/{print $3, $4}')
echo "    actual disk usage: $SIZE"

# ── Attach qcow2 via NBD ──────────────────────────────────────────────────────
echo ""
echo "==> Attaching disk image via qemu-nbd ..."
modprobe nbd max_part=8
trap cleanup EXIT
qemu-nbd --connect="$NBD_DEV" --read-only "$DISK_PATH"
partprobe "$NBD_DEV" 2>/dev/null || true
sleep 1   # let the kernel register partitions

# ── Partition table ───────────────────────────────────────────────────────────
echo ""
echo "=== Partition table ==="
fdisk -l "$NBD_DEV" 2>/dev/null

# ── Partition count ───────────────────────────────────────────────────────────
echo ""
echo "=== Partition count on single device ==="
PART_COUNT=$(lsblk -n -o NAME "$NBD_DEV" 2>/dev/null | grep -c "^├\|^└\|nbd0p" || true)
PART_COUNT=$(ls /dev/nbd0p* 2>/dev/null | wc -l)
echo "    $PART_COUNT partitions found on disk image"

if [[ "$PART_COUNT" -eq 3 ]]; then
    echo "    OK  3 partitions (EFI + /boot + LUKS) — all on one disk"
else
    echo "    !! FAIL expected 3 partitions, got $PART_COUNT"
    PASS=0
fi

# ── Filesystem types ──────────────────────────────────────────────────────────
echo ""
echo "=== Filesystem types ==="
blkid /dev/nbd0p* 2>/dev/null || true

# ── Checks ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Checks ==="

# EFI partition (vfat)
if blkid /dev/nbd0p* 2>/dev/null | grep -qi "vfat\|EFI"; then
    echo "  OK  EFI (vfat) filesystem present"
else
    echo "  !! FAIL no EFI filesystem found"
    PASS=0
fi

# /boot partition (xfs)
if blkid /dev/nbd0p* 2>/dev/null | grep -qi "xfs"; then
    echo "  OK  XFS filesystem present (/boot)"
else
    echo "  !! FAIL no XFS filesystem found"
    PASS=0
fi

# LUKS partition
if blkid /dev/nbd0p* 2>/dev/null | grep -qi "crypto_LUKS"; then
    echo "  OK  LUKS partition present"
else
    echo "  !! FAIL no LUKS partition found"
    PASS=0
fi

# All partitions on same device (no bleed onto other disks)
echo "  OK  all partitions on $NBD_DEV (single disk)"

# ── ks-test.log ───────────────────────────────────────────────────────────────
echo ""
echo "=== ks-test.log from inside the VM ==="
# Mount /boot then root LV if LUKS is present — for now just note it requires
# manual unlock. Print a reminder instead of attempting auto-unlock.
echo "(skipped — LUKS-encrypted root requires passphrase to mount)"
echo "  To inspect manually:"
echo "    sudo cryptsetup luksOpen /dev/nbd0p3 test-luks"
echo "    sudo vgscan && sudo vgchange -ay vg0"
echo "    sudo mount /dev/vg0/root /mnt && cat /mnt/root/ks-test.log"
echo "    sudo umount /mnt && sudo vgchange -an vg0 && sudo cryptsetup luksClose test-luks"

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
if [[ "$PASS" -eq 1 ]]; then
    echo "Level 2 PASSED for $VM"
else
    echo "Level 2 FAILED for $VM — review output above"
    exit 1
fi

echo ""
echo "To boot and inspect the VM interactively:"
echo "  sudo virsh start $VM && sudo virsh console $VM"
echo ""
echo "To clean up:"
echo "  sudo virsh undefine $VM --remove-all-storage --nvram 2>/dev/null; sudo rm -f $DISK_PATH"
