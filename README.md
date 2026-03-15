# AlmaLinux 10.1 Daily Driver

Generic fixes for hardware and software that doesn't work out of the box
on AlmaLinux 10.1 / RHEL 10.

---

## Quick Install

The `kickstart.ks` file fully automates the AlmaLinux install — no clicking
through the Anaconda installer. It will pause once to ask for your LUKS
passphrase, then run completely unattended.

### Steps

1. **Download the AlmaLinux 10.1 minimal or DVD ISO** and write it to a USB drive:
   ```bash
   sudo dd if=AlmaLinux-10.1-x86_64-dvd.iso of=/dev/sdX bs=4M status=progress
   ```

2. **Boot from the USB.** When the GRUB menu appears, press `e` to edit the
   boot entry.

3. **Add the Kickstart location** to the `linuxefi` line:
   ```
   inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
   ```
   The line should look like:
   ```
   linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=... inst.ks=https://raw.githubusercontent.com/korciuch/al10-daily-driver/main/kickstart.ks
   ```

4. Press `Ctrl+X` to boot. Anaconda will prompt for your **LUKS passphrase**,
   then proceed fully unattended.

5. After reboot, log in as `admin` / `admin` and run:
   ```bash
   bash ~/setup.sh
   ```
   This runs the interactive module selector to install hardware fixes,
   codecs, and other post-install configuration.

### Using a local copy of the Kickstart (offline / no internet at boot)

Copy `kickstart.ks` to the USB drive and reference it via the `hd:` scheme:
```
inst.ks=hd:LABEL=MY_USB:/kickstart.ks
```

Or serve it over HTTP on your local network:
```bash
python3 -m http.server 8080   # run on another machine
# then at boot:
inst.ks=http://192.168.1.x:8080/kickstart.ks
```

---

## What the Kickstart installs

- AlmaLinux 10.1 with GNOME, XFS on LVM on LUKS2
- CRB, EPEL, and RPM Fusion repos pre-configured
- Build tools: `gcc`, `make`, `dkms`, `kernel-devel`, `git`
- `admin` user with default password (you will be prompted to change it on first login)
- Root account locked
- Clones this repo to `/opt/al10-daily-driver` and drops `~/setup.sh`

---

## Hardware-specific fixes

Hardware-specific fixes live in their own repos:

| Repo | Hardware | What it fixes |
|------|----------|--------------|
| [al10-intel-ipu6](https://github.com/korciuch/al10-intel-ipu6) | Intel Meteor Lake (Dell XPS 16 9640) | IPU6 camera + SOF audio |
