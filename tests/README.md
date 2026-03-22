# Kickstart Partitioning Tests

Verifies that the kickstart `%pre` block correctly targets all partitions to
the detected disk via `--ondisk`. Designed to catch a regression where
`/boot/efi` and `/boot` land on the USB install stick instead of the NVMe
(see issue #7).

There are two levels of testing with increasing cost and fidelity.

---

## Level 1 — Local simulation (no VM, ~5 seconds)

```bash
bash tests/test-kickstart-pre-simulation.sh
```

**What it does:** Replicates the `%pre` disk detection and include-file
generation locally, writing output to `/tmp/ks-sim/`. Nothing is installed or
modified on the system.

**What it checks:**
- Every `clearpart`, `bootloader`, and `part` command in `disk-include`
  references the detected disk by name
- `/var/vantage` has positive space to grow after fixed LVM volumes are
  accounted for

**Interpreting output:**

```
  OK  'clearpart' targets sda
  OK  'bootloader' targets sda
  OK  '/boot/efi' targets sda
  OK  '/boot ' targets sda
  OK  'pv.01' targets sda
  OK  /var/vantage has space to grow

Level 1 PASSED — disk-include is correct for sda
```

Any `!! FAIL` line means a `part` command does not reference the correct disk —
the kickstart `%pre` block has a bug.

---

## Level 2 — VM install + disk inspection (~5–10 min each)

Requires: `libvirtd` running, `edk2-ovmf` installed, and the AlmaLinux 10.1
minimal ISO at `/var/lib/libvirt/images/AlmaLinux-10.1-x86_64-minimal.iso`.

Two VM sizes exercise the two layout branches in `%pre`:

| Script | Disk | Layout triggered |
|--------|------|-----------------|
| `tests/test-l2-vm-small.sh` | 40 GB | VM layout (`< 100 GB`) |
| `tests/test-l2-vm-large.sh` | 200 GB | Production layout (`≥ 100 GB`) |

Both use thin-provisioned qcow2 images — actual host disk usage is ~2 GB per
run regardless of virtual disk size.

### Run

```bash
sudo bash tests/test-l2-vm-small.sh
# ... wait for install to finish and VM to shut down ...
sudo bash tests/test-l2-verify.sh test-ks-small

sudo bash tests/test-l2-vm-large.sh
sudo bash tests/test-l2-verify.sh test-ks-large
```

Watch the console for the `%pre` marker lines confirming which layout was
selected:

```
TEST %pre: detected disk=vda size=40960MB
TEST %pre: VM layout selected (< 100 GB)
```

or

```
TEST %pre: detected disk=vda size=204800MB
TEST %pre: production layout selected (>= 100 GB)
```

If neither line appears, the kickstart was not injected — check that the ISO
path is correct and `--initrd-inject` is supported by your `virt-install`
version.

### Verify

```bash
sudo bash tests/test-l2-verify.sh <vm-name>
```

Uses `qemu-nbd` to mount the installed qcow2 as a block device and inspects
it with `fdisk` and `blkid`. Does not require `libguestfs`.

**What it checks:**
- Exactly 3 GPT partitions on a single disk
- Partition 1: `vfat` (EFI System Partition)
- Partition 2: `xfs` (`/boot`)
- Partition 3: `crypto_LUKS` (LUKS2 container holding the LVM PV)

**Passing output:**

```
=== Partition count on single device ===
    3 partitions found on disk image
    OK  3 partitions (EFI + /boot + LUKS) — all on one disk

=== Checks ===
  OK  EFI (vfat) filesystem present
  OK  XFS filesystem present (/boot)
  OK  LUKS partition present
  OK  all partitions on /dev/nbd0 (single disk)

Level 2 PASSED for test-ks-small
```

**Failing output** (partition count 0) most commonly means:
- The install did not complete — check that `--passphrase` is set in the
  kickstart `%pre` block (LUKS requires a non-interactive passphrase)
- `libvirtd` was not running when the VM was launched

### Inspecting the installed root filesystem

The root LV is LUKS-encrypted. To read `/root/ks-test.log` written by `%post`:

```bash
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 /var/lib/libvirt/images/test-ks-small.qcow2
sudo cryptsetup luksOpen /dev/nbd0p3 test-luks   # passphrase: testpass123
sudo vgscan && sudo vgchange -ay vg0
sudo mount /dev/vg0/root /mnt
cat /mnt/root/ks-test.log
sudo umount /mnt
sudo vgchange -an vg0 && sudo cryptsetup luksClose test-luks
sudo qemu-nbd --disconnect /dev/nbd0
```

### Cleanup

```bash
sudo virsh undefine test-ks-small --remove-all-storage --nvram 2>/dev/null
sudo virsh undefine test-ks-large --remove-all-storage --nvram 2>/dev/null
sudo rm -f /var/lib/libvirt/images/test-ks-small.qcow2 \
           /var/lib/libvirt/images/test-ks-large.qcow2
```

---

## Prerequisites

```bash
sudo systemctl start libvirtd
sudo dnf install -y edk2-ovmf qemu-img
```

`libguestfs-tools` is **not** required — the verify script uses `qemu-nbd`
instead, which works in nested VM environments where `libguestfs` cannot
launch its appliance.
