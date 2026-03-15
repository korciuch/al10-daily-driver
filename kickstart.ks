#version=RHEL10
# AlmaLinux 10.1 — Daily Driver Kickstart
# Usage: append inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
#        to the boot command line, or point to a local copy on USB.
#
# Anaconda will prompt once for the LUKS passphrase, then run fully unattended.

# ── Install source ────────────────────────────────────────────────────────────
url --mirrorlist=https://mirrors.almalinux.org/mirrorlist/10/BaseOS
repo --name=AppStream --mirrorlist=https://mirrors.almalinux.org/mirrorlist/10/AppStream
repo --name=extras --mirrorlist=https://mirrors.almalinux.org/mirrorlist/10/extras
repo --name=CRB --mirrorlist=https://mirrors.almalinux.org/mirrorlist/10/CRB

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
ignoredisk --only-use=nvme0n1
clearpart --all --initlabel --drives=nvme0n1
bootloader --location=mbr --boot-drive=nvme0n1

# Prompt for LUKS passphrase — only interactive pause in the install
part /boot/efi --fstype=efi  --size=512  --ondrive=nvme0n1
part /boot     --fstype=xfs  --size=1024 --ondrive=nvme0n1
part pv.01     --size=1      --grow      --ondrive=nvme0n1 --encrypted --luks-version=luks2

volgroup vg0 pv.01
logvol /    --vgname=vg0 --fstype=xfs --size=1 --grow --name=root
logvol swap --vgname=vg0 --fstype=swap --size=8192  --name=swap

# ── Package selection ─────────────────────────────────────────────────────────
%packages
@^graphical-server-environment
@base
@core
@development
@hardware-support
@network-file-system-client

# Build tools (needed for DKMS)
gcc
make
dkms
kernel-devel
git
curl

# EPEL bootstrap (RPM Fusion depends on it)
epel-release

# CLI utilities
bash-completion
htop
tmux
vim
%end

# ── Post-install ──────────────────────────────────────────────────────────────
%post --log=/var/log/kickstart-post.log
set -euo pipefail

echo "==> Enabling CRB repo"
dnf config-manager --set-enabled crb -y

echo "==> Installing RPM Fusion (free + nonfree)"
dnf install -y distribution-gpg-keys
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-el-$(rpm -E %rhel)
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-nonfree-el-$(rpm -E %rhel)
dnf --setopt=localpkg_gpgcheck=1 install -y \
    https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm

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
