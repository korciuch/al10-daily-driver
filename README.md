# AlmaLinux 10.1 Daily Driver

A reproducible, automated install for AlmaLinux 10.1 as a daily driver on
modern hardware (currently targeting the Dell XPS 16 9640 / Intel Meteor Lake).

AlmaLinux 10.1 ships with gaps — missing camera drivers, broken audio firmware,
no multimedia codecs, and no straightforward way to get a working desktop in one
shot. This repo closes those gaps through two components:

- **`kickstart.ks`** — a fully unattended Anaconda kickstart that handles disk
  partitioning (XFS on LVM on LUKS2), user setup, and base package installation
  in a single boot. No clicking through an installer, no manual post-install
  steps forgotten between reinstalls.

- **`setup.sh`** — an interactive module selector (run after first login) that
  patches hardware, installs optional software, and configures developer tooling.
  Each module is independent and idempotent.

The kickstart + setup.sh split means the full system can be rebuilt from scratch
in under 30 minutes with a single USB flash and one script run — making it
practical to iterate on the config rather than accumulate manual one-off changes.

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

This produces `al10-daily-driver.iso` (~8.5 GB).

> **DVD ISO required** — the minimal ISO lacks EFI partition data and `mkksiso` will fail with xorriso exit 32.
> **USB drive must be at least 9 GB.**

### Step 2 — Write to USB

```bash
sudo dd if=al10-daily-driver.iso of=/dev/sdX bs=4M status=progress
sudo eject /dev/sdX
```

### Step 3 — Boot and install

Boot from the USB. Anaconda will pause once to ask for your **LUKS
passphrase**, then run completely unattended. No installer UI.

> **Minimum disk size: 200 GB.** The production partition layout reserves ~186 GB in
> fixed-size mounts before `/var/vantage` gets the remainder. Disks under 100 GB
> use a smaller test layout (~23 GB fixed).

### Step 4 — First login

Log in as `admin` / `admin` and run:

```bash
bash ~/setup.sh
```

This runs the interactive module selector to install hardware fixes,
codecs, and other post-install configuration.

---

## What gets installed

- AlmaLinux 10.1, XFS on LVM on LUKS2
- GNOME desktop on bare metal (skipped automatically in VMs)
- CRB, EPEL, and RPM Fusion repos pre-configured
- Build tools: `gcc`, `make`, `git` (Development Tools group)
- `admin` user (default password `admin`, forced change on first login)
- Root account locked
- This repo cloned to `/opt/al10-daily-driver`

---

## VM Testing

### Prerequisites

**Start libvirt sockets** (AlmaLinux 10 uses modular daemons — do this once after install):

```bash
for drv in qemu network nodedev nwfilter secret storage interface; do
    sudo systemctl start virt${drv}d{,-ro,-admin}.socket
done
```

Download the ISO(s) you need and place them in `/var/lib/libvirt/images/`:

```bash
# Minimal ISO (~800 MB) — for fast partition/kickstart logic testing
sudo curl -L -o /var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso \
    https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10.1-x86_64-minimal.iso

# DVD ISO (~8.5 GB) — required for full end-to-end testing and build-iso.sh
sudo curl -L -o /var/lib/libvirt/images/AlmaLinux-10.1-x86_64-dvd.iso \
    https://repo.almalinux.org/almalinux/10/isos/x86_64/AlmaLinux-10.1-x86_64-dvd.iso
```

### Minimal ISO — fast iteration (partitions, %pre prompts, %post logic)

Use when testing kickstart changes that don't require the full package install.
Faster boot, smaller download. `%post` will fail on missing packages — that's expected.

```bash
sudo virt-install \
  --name al10-test \
  --memory 4096 \
  --vcpus 2 \
  --disk size=150 \
  --check disk_size=off \
  --location /var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso \
  --initrd-inject $(pwd)/kickstart.ks \
  --extra-args "inst.ks=file:///kickstart.ks console=ttyS0" \
  --graphics none \
  --os-variant almalinux10 \
  --boot uefi
```

### DVD ISO — full end-to-end test (before flashing to USB)

Use before reflashing real hardware. Runs the complete `%post` including
EPEL, RPM Fusion, dev tools, and repo clone. Takes longer but validates
the full install path.

```bash
sudo virt-install \
  --name al10-test \
  --memory 4096 \
  --vcpus 2 \
  --disk size=150 \
  --check disk_size=off \
  --location /var/lib/libvirt/images/AlmaLinux-10.1-x86_64-dvd.iso \
  --initrd-inject $(pwd)/kickstart.ks \
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

### OBS Studio + IPU6 camera

The IPU6 camera does not expose a standard V4L2 stream — it requires `libcamera`
as an abstraction layer. OBS must use the **PipeWire** camera source, not the
V4L2 one:

1. In OBS, click **+** to add a source
2. Choose **Video Capture Device (PipeWire)** (not the plain V4L2 option)
3. Select the camera from the device list

The `obs` module in `setup.sh` handles this automatically: it installs
`libcamera-v4l2` and grants OBS Flatpak device access via
`flatpak override --user --device=all`.
