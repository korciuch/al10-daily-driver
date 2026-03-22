#version=RHEL10
# AlmaLinux 10.1 — Daily Driver Kickstart
# Usage: append inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
#        to the boot command line, or point to a local copy on USB.
#
# Anaconda will prompt for admin password and LUKS passphrase, then run unattended.

# ── Install source ────────────────────────────────────────────────────────────
# Source is provided by the boot medium (ISO or inst.repo= boot arg).
# Do not set url/repo here — it conflicts with virt-install --location
# and with inst.ks= boot arg installs where Anaconda auto-detects the source.

# ── Locale & keyboard ─────────────────────────────────────────────────────────
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone America/Los_Angeles --utc

# ── Network ───────────────────────────────────────────────────────────────────
network --bootproto=dhcp --device=link --activate
network --hostname=localhost.localdomain

# ── Security ──────────────────────────────────────────────────────────────────
selinux --enforcing
firewall --enabled --service=ssh

# ── Users ─────────────────────────────────────────────────────────────────────
rootpw --lock
# Placeholder password — overwritten by %post --nochroot using value from %pre
user --name=admin --groups=wheel --password=changeme --plaintext
firstboot --disable

# ── Disk & partitioning ───────────────────────────────────────────────────────
# %pre detects the target disk ($DISK) and writes /tmp/disk-include so that
# clearpart, bootloader, and all part commands explicitly target that disk via
# --ondisk / --drives / --boot-drive. Without --ondisk, Anaconda may place
# /boot/efi and /boot on the USB install stick instead of the NVMe. See #7.
%include /tmp/disk-include

volgroup vg0 pv.01

# Logical volume sizes — all constants, scaled by disk size.
# < 100 GB (test/VM): small layout. >= 100 GB (production): full layout.
# /var/vantage gets the remainder with --grow.
%include /tmp/part-include

# ── Pre-install: select partition sizes by disk size ─────────────────────────
%pre --interpreter /bin/bash

# ── Admin password ────────────────────────────────────────────────────────────
# Use read -s for reliable password input during early %pre boot environment.
while true; do
    echo -n "Set password for admin user: " > /dev/tty
    read -s PASS1 < /dev/tty; echo "" > /dev/tty
    echo -n "Confirm password: " > /dev/tty
    read -s PASS2 < /dev/tty; echo "" > /dev/tty
    [ "$PASS1" = "$PASS2" ] && break
    echo "Passwords do not match. Try again." > /dev/tty
done
echo "${PASS1}" > /tmp/admin-pass

# ── Partition sizes ───────────────────────────────────────────────────────────
DISK=$(lsblk -d -n -o NAME,RM,TYPE 2>/dev/null | awk '$2==0 && $3=="disk"{print $1}' | head -1)
DISK_MB=0
[ -n "$DISK" ] && DISK_MB=$(lsblk -b -d -n -o SIZE /dev/$DISK 2>/dev/null | awk '{print int($1/1024/1024)}')
[ "$DISK_MB" -eq 0 ] && DISK_MB=40960   # fallback: assume 40 GB

# Write disk-include so all part commands target $DISK explicitly.
# This prevents Anaconda from placing /boot/efi and /boot on the USB install
# stick when multiple block devices are visible during install. See issue #7.
cat > /tmp/disk-include <<DISKEOF
clearpart --all --initlabel --drives=${DISK}
bootloader --location=mbr --boot-drive=${DISK}
part /boot/efi --fstype=efi  --size=600  --asprimary --ondisk=${DISK}
part /boot     --fstype=xfs  --size=1024             --ondisk=${DISK}
part pv.01     --size=1      --grow      --encrypted --luks-version=luks2 --ondisk=${DISK}
DISKEOF

if [ "$DISK_MB" -lt 102400 ]; then
    # Test / VM layout (< 100 GB)
    ROOT_MB=4096
    HOME_MB=5120
    SWAP_MB=4096
    TMP_MB=1024
    VAR_MB=4096
    VAR_TMP_MB=1024
    VAR_LOG_MB=2048
    VAR_LOG_AUDIT_MB=2048
else
    # Production layout (>= 100 GB)
    ROOT_MB=71680
    HOME_MB=51200
    SWAP_MB=16384
    TMP_MB=5120
    VAR_MB=20480
    VAR_TMP_MB=5120
    VAR_LOG_MB=10240
    VAR_LOG_AUDIT_MB=10240
fi

cat > /tmp/part-include <<EOF
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
%end

# ── Package selection ─────────────────────────────────────────────────────────
# Keep this minimal — only packages available on the AlmaLinux minimal ISO.
# Everything else (GNOME, DKMS, EPEL, build tools) is installed in %post
# after the network is up and repos are configured.
%packages
@core
curl
%end

# ── Apply admin password (runs before chroot, /tmp is shared with %pre) ───────
%post --nochroot
PASS=$(cat /tmp/admin-pass)
echo "admin:${PASS}" | chroot /mnt/sysimage chpasswd
rm -f /tmp/admin-pass
%end

# ── Post-install ──────────────────────────────────────────────────────────────
%post --log=/var/log/kickstart-post.log
set -euo pipefail

echo "==> Enabling CRB repo"
dnf config-manager --set-enabled crb -y

echo "==> Installing EPEL"
dnf install -y epel-release

echo "==> Installing RPM Fusion (free + nonfree)"
dnf install -y distribution-gpg-keys
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-el-$(rpm -E %rhel)
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-nonfree-el-$(rpm -E %rhel)
dnf --setopt=localpkg_gpgcheck=1 install -y \
    https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

echo "==> Installing dev tools"
dnf groupinstall -y "Development Tools"
dnf install -y bash-completion htop tmux vim fuse fuse-libs

if ! systemd-detect-virt -q; then
    echo "==> Bare metal detected — installing Server with GUI"
    dnf groupinstall -y "Server with GUI"
    systemctl set-default graphical.target
    dnf install -y qemu-kvm qemu-img libvirt virt-install virt-viewer edk2-ovmf lorax
    for drv in qemu network nodedev nwfilter secret storage interface; do
        systemctl enable virt${drv}d{,-ro,-admin}.socket
    done
else
    echo "==> VM detected — skipping Server with GUI"
fi

echo "==> Installing GitHub CLI"
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh libsecret

echo "==> Cloning al10-daily-driver"
git clone https://github.com/korciuch/al10-daily-driver.git /opt/al10-daily-driver
chown -R admin:admin /opt/al10-daily-driver

echo "==> Creating setup shortcut for admin user"
cat > /home/admin/setup.sh <<'EOF'
#!/usr/bin/env bash
# Run this after first login to complete your daily driver setup.
sudo bash /opt/al10-daily-driver/setup.sh
EOF
chmod +x /home/admin/setup.sh
chown admin:admin /home/admin/setup.sh

echo "==> Post-install complete. Run ~/setup.sh after first login."
%end

# ── Reboot when done ──────────────────────────────────────────────────────────
reboot
