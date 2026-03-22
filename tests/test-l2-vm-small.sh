#!/usr/bin/env bash
# Level 2 VM test — 40 GB disk (triggers VM layout < 100 GB)
# sudo bash tests/test-l2-vm-small.sh  (from repo root)
#
# Requires: libvirtd running, minimal ISO downloaded

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="/var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso"
DISK="/var/lib/libvirt/images/test-ks-small.qcow2"
VM="test-ks-small"
KS="$REPO_DIR/tests/test-kickstart.ks"

[[ -f "$ISO" ]] || { echo "ERROR: ISO not found at $ISO"; exit 1; }
[[ -f "$KS"  ]] || { echo "ERROR: kickstart not found at $KS"; exit 1; }

systemctl is-active libvirtd >/dev/null 2>&1 \
    || { echo "ERROR: libvirtd not running — sudo systemctl start libvirtd"; exit 1; }

rpm -q edk2-ovmf >/dev/null 2>&1 \
    || { echo "ERROR: edk2-ovmf not installed — sudo dnf install -y edk2-ovmf"; exit 1; }

# Clean up any previous test VM
virsh destroy "$VM" 2>/dev/null || true
virsh undefine "$VM" --remove-all-storage --nvram 2>/dev/null || true

echo "==> Launching 40 GB VM install (VM layout expected)..."
echo "    Watch the console for '%pre: detected disk' and 'VM layout selected'"
echo ""

virt-install \
    --name "$VM" \
    --memory 4096 \
    --vcpus 2 \
    --disk path="$DISK",size=40,format=qcow2 \
    --check disk_size=off \
    --location "$ISO" \
    --os-variant almalinux10 \
    --graphics none \
    --console pty,target_type=serial \
    --extra-args "inst.ks=file:///test-kickstart.ks console=ttyS0" \
    --initrd-inject "$KS" \
    --boot uefi \
    --wait -1 \
    --noreboot

echo ""
echo "==> Install complete. Run verification:"
echo "    sudo bash $REPO_DIR/tests/test-l2-verify.sh $VM"
