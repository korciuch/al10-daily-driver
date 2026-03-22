#!/usr/bin/env bash
# Level 2 VM test — 200 GB disk (triggers production layout >= 100 GB)
# sudo bash tests/test-l2-vm-large.sh  (from repo root)
#
# Requires: libvirtd running, minimal ISO downloaded
# NOTE: uses a thin-provisioned qcow2 — actual disk usage will be much less
# NOTE: 200 GB required because production LVM volumes total ~186 GB

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="/var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso"
DISK="/var/lib/libvirt/images/test-ks-large.qcow2"
VM="test-ks-large"
KS="$REPO_DIR/tests/test-kickstart.ks"

[[ -f "$ISO" ]] || { echo "ERROR: ISO not found at $ISO"; exit 1; }
[[ -f "$KS"  ]] || { echo "ERROR: kickstart not found at $KS"; exit 1; }

systemctl is-active libvirtd >/dev/null 2>&1 \
    || { echo "ERROR: libvirtd not running — sudo systemctl start libvirtd"; exit 1; }

rpm -q edk2-ovmf >/dev/null 2>&1 \
    || { echo "ERROR: edk2-ovmf not installed — sudo dnf install -y edk2-ovmf"; exit 1; }

virsh destroy "$VM" 2>/dev/null || true
virsh undefine "$VM" --remove-all-storage --nvram 2>/dev/null || true

echo "==> Launching 200 GB VM install (production layout expected)..."
echo "    Watch for '%pre: production layout selected'"
echo ""

virt-install \
    --name "$VM" \
    --memory 4096 \
    --vcpus 2 \
    --disk path="$DISK",size=200,format=qcow2 \
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
