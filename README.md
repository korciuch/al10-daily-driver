# AlmaLinux 10.1 Daily Driver (Meteor Lake)

Fixes for hardware that doesn't work out of the box on AlmaLinux 10.1 / RHEL 10
on Intel Meteor Lake laptops.

**Tested on:** Dell XPS 16 9640 · AlmaLinux 10.1 · kernel 6.12.0-124.43.1.el10_1.x86_64

---

## Fixes

| Fix | What it does |
|-----|-------------|
| [camera/](https://github.com/korciuch/al10-intel-ipu6) | Intel IPU6 camera — DKMS patches, VSC firmware, DKMS build |
| [audio/](audio/) | Intel MTL SOF audio — IPC4 firmware from upstream sof-bin |

---

## Quick Start

```bash
# Camera (see al10-intel-ipu6 for full details)
git clone --recurse-submodules https://github.com/korciuch/al10-intel-ipu6.git
sudo bash al10-intel-ipu6/setup.sh

# Audio
git clone https://github.com/korciuch/al10-daily-driver.git
sudo bash al10-daily-driver/audio/setup.sh
```

Reboot after both scripts complete.

---

## Why separate repos?

The camera fix (`al10-intel-ipu6`) is self-contained — it carries its own
pinned submodules and patches and is useful independently. This repo
(`al10-daily-driver`) is the broader collection; it references camera
as an external repo and owns the audio fix directly.
