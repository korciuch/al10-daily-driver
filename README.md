# AlmaLinux 10.1 Daily Driver

Generic fixes for hardware and software that doesn't work out of the box
on AlmaLinux 10.1 / RHEL 10.

---

## Quick Install

### Step 1 — Build a custom ISO

Embeds `kickstart.ks` directly into the AlmaLinux ISO so the install starts
automatically on boot — no GRUB editing needed.

```bash
# Install lorax (provides mkksiso) if not already present
sudo dnf install -y lorax

# Download the AlmaLinux 10.1 DVD ISO, then:
git clone https://github.com/korciuch/al10-daily-driver.git
bash al10-daily-driver/build-iso.sh AlmaLinux-10.1-x86_64-dvd.iso
```

This produces `al10-daily-driver.iso`.

### Step 2 — Write to USB

```bash
sudo dd if=al10-daily-driver.iso of=/dev/sdX bs=4M status=progress
sudo eject /dev/sdX
```

### Step 3 — Boot and install

Boot from the USB. Anaconda will pause once to ask for your **LUKS
passphrase**, then run completely unattended. No installer UI.

### Step 4 — First login

Log in as `admin` / `admin` and run:

```bash
bash ~/setup.sh
```

This runs the interactive module selector to install hardware fixes,
codecs, and other post-install configuration.

---

## What gets installed

- AlmaLinux 10.1 with GNOME, XFS on LVM on LUKS2
- CRB, EPEL, and RPM Fusion repos pre-configured
- Build tools: `gcc`, `make`, `dkms`, `kernel-devel`, `git`
- `admin` user (default password, forced change on first login)
- Root account locked
- This repo cloned to `/opt/al10-daily-driver`

---

## VM Testing

Test the kickstart before flashing to USB:

```bash
sudo virt-install \
  --name al10-test \
  --memory 4096 \
  --vcpus 2 \
  --disk size=40 \
  --location /var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso \
  --initrd-inject /home/admin/Drivers/al10-daily-driver/kickstart.ks \
  --extra-args "inst.ks=file:///kickstart.ks console=ttyS0" \
  --graphics none \
  --os-variant almalinux10 \
  --boot uefi
```

> `--boot uefi` is required — kickstart has an EFI partition, BIOS mode causes a "biosboot partition required" error.
> `edk2-ovmf` must be installed: `sudo dnf install -y edk2-ovmf`

`Server with GUI` is automatically skipped in VMs (`systemd-detect-virt` detects KVM).
Check post-install log: `sudo virsh console al10-test` → `cat /var/log/kickstart-post.log`

**Cleanup:**
```bash
sudo virsh destroy al10-test                            # if still running
sudo virsh undefine al10-test --remove-all-storage --nvram
```

> `--nvram` is required — omitting it will error on UEFI-booted VMs.

---

## Fallback: manual GRUB edit

If you can't run `build-iso.sh` (e.g. on a non-Linux machine), boot the
stock AlmaLinux ISO, press `e` on the GRUB menu, and append to the
`linuxefi` line:

```
inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
```

---

## Hardware-specific fixes

| Repo | Hardware | What it fixes |
|------|----------|--------------|
| [al10-intel-ipu6](https://github.com/korciuch/al10-intel-ipu6) | Intel Meteor Lake (Dell XPS 16 9640) | IPU6 camera + SOF audio |
