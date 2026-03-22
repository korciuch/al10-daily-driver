#version=RHEL10
# Trimmed kickstart for Level 2 partitioning test.
# Non-interactive (hardcoded password), minimal %post.
# Tests ONLY that disk-include generates correct --ondisk targeting.

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone America/Los_Angeles --utc
network --bootproto=dhcp --device=link --activate
selinux --permissive
firewall --disabled
rootpw --lock
user --name=admin --groups=wheel --password=testpass123 --plaintext
firstboot --disable

%include /tmp/disk-include
volgroup vg0 pv.01
%include /tmp/part-include

%pre --interpreter /bin/bash
# Detect first non-removable disk (same logic as production kickstart)
DISK=$(lsblk -d -n -o NAME,RM,TYPE 2>/dev/null | awk '$2==0 && $3=="disk"{print $1}' | head -1)
DISK_MB=0
[ -n "$DISK" ] && DISK_MB=$(lsblk -b -d -n -o SIZE /dev/$DISK 2>/dev/null | awk '{print int($1/1024/1024)}')
[ "$DISK_MB" -eq 0 ] && DISK_MB=40960

echo "TEST %pre: detected disk=$DISK size=${DISK_MB}MB" >> /dev/tty

cat > /tmp/disk-include <<DISKEOF
clearpart --all --initlabel --drives=${DISK}
bootloader --location=mbr --boot-drive=${DISK}
part /boot/efi --fstype=efi  --size=600  --asprimary --ondisk=${DISK}
part /boot     --fstype=xfs  --size=1024             --ondisk=${DISK}
part pv.01     --size=1      --grow      --encrypted --luks-version=luks2 --passphrase=testpass123 --ondisk=${DISK}
DISKEOF

if [ "$DISK_MB" -lt 102400 ]; then
    ROOT_MB=4096; HOME_MB=5120; SWAP_MB=4096; TMP_MB=1024
    VAR_MB=4096; VAR_TMP_MB=1024; VAR_LOG_MB=2048; VAR_LOG_AUDIT_MB=2048
    echo "TEST %pre: VM layout selected (< 100 GB)" >> /dev/tty
else
    ROOT_MB=71680; HOME_MB=51200; SWAP_MB=16384; TMP_MB=5120
    VAR_MB=20480; VAR_TMP_MB=5120; VAR_LOG_MB=10240; VAR_LOG_AUDIT_MB=10240
    echo "TEST %pre: production layout selected (>= 100 GB)" >> /dev/tty
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

%packages
@core
%end

# Minimal %post — write disk layout to a file we can inspect after install
%post --log=/root/ks-test.log
echo "=== lsblk ===" >> /root/ks-test.log
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT >> /root/ks-test.log

echo "=== partition table ===" >> /root/ks-test.log
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,PARTLABEL >> /root/ks-test.log

echo "=== findmnt /boot/efi ===" >> /root/ks-test.log
findmnt /boot/efi >> /root/ks-test.log 2>&1 || echo "/boot/efi NOT MOUNTED" >> /root/ks-test.log

echo "=== findmnt /boot ===" >> /root/ks-test.log
findmnt /boot >> /root/ks-test.log 2>&1 || echo "/boot NOT MOUNTED" >> /root/ks-test.log
%end

reboot
