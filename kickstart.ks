#version=RHEL10
# AlmaLinux 10.1 — Daily Driver Kickstart
# Usage: append inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
#        to the boot command line, or point to a local copy on USB.
#
# Anaconda will prompt once for the LUKS passphrase, then run fully unattended.

# ── Install source ────────────────────────────────────────────────────────────
# Source is provided by the boot medium (ISO or inst.repo= boot arg).
# Do not set url/repo here — it conflicts with virt-install --location
# and with inst.ks= boot arg installs where Anaconda auto-detects the source.

# ── Locale & keyboard ─────────────────────────────────────────────────────────
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone America/Chicago --utc

# ── Network ───────────────────────────────────────────────────────────────────
network --bootproto=dhcp --device=link --activate
network --hostname=localhost.localdomain

# ── Security ──────────────────────────────────────────────────────────────────
selinux --enforcing
firewall --enabled --service=ssh

# ── Users ─────────────────────────────────────────────────────────────────────
rootpw --lock
user --name=admin --groups=wheel --password=admin --plaintext
# Change password on first login
firstboot --enable

# ── Disk & partitioning ───────────────────────────────────────────────────────
# Auto-detect the first available disk so this works both in a VM (vda)
# and on the real machine (nvme0n1). clearpart --all wipes everything.
clearpart --all --initlabel
bootloader --location=mbr

# Prompt for LUKS passphrase — only interactive pause in the install
part /boot/efi --fstype=efi  --size=512  --asprimary
part /boot     --fstype=xfs  --size=1024
part pv.01     --size=1      --grow      --encrypted --luks-version=luks2

volgroup vg0 pv.01
logvol /    --vgname=vg0 --fstype=xfs --size=1 --grow --name=root
logvol swap --vgname=vg0 --fstype=swap --size=8192  --name=swap

# ── Package selection ─────────────────────────────────────────────────────────
# Keep this minimal — only packages available on the AlmaLinux minimal ISO.
# Everything else (GNOME, DKMS, EPEL, build tools) is installed in %post
# after the network is up and repos are configured.
%packages
@core
curl
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
dnf install -y bash-completion htop tmux vim

if ! systemd-detect-virt -q; then
    echo "==> Bare metal detected — installing Server with GUI"
    dnf groupinstall -y "Server with GUI"
    systemctl set-default graphical.target
else
    echo "==> VM detected — skipping Server with GUI"
fi

echo "==> Cloning al10-daily-driver"
git clone https://github.com/korciuch/al10-daily-driver.git /opt/al10-daily-driver

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
