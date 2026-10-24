# 01 - Base installation

From a blank Arch Linux ISO to an encrypted, Secure Boot enabled system that boots a
Unified Kernel Image (UKI) straight from the firmware, unlocks the disk with the TPM,
and has CachyOS x86-64-v4 repositories enabled. No `archinstall`.

The desktop (KDE Plasma, SDDM, audio, NVIDIA driver, snapshots) is in
[02-desktop.md](02-desktop.md). Hardware tuning (EDID/HDR override, power, audio quirk,
GPU switching) is in the [docs/03](03-g14-hardware-and-power.md) guide, and the custom kernel/Plymouth packages are
in [04-custom-packages.md](04-custom-packages.md).

Tested on: **ROG Zephyrus G14 GA403GM** (Ryzen AI 9 465, Radeon 880M iGPU, RTX 5060
Laptop dGPU, 32 GB RAM, KIOXIA BG6 1 TB NVMe, Intel AX210 Wi-Fi), BIOS GA403GM.302.
Other GA403 variants are very likely the same for everything in this file; the parts
that depend on this exact model are marked **[GA403GM]**.

Reference files used below are under [`system/`](../system) at their real target path.

## Contents

1. [Final layout](#1-final-layout)
2. [Before you start: firmware settings](#2-before-you-start-firmware-settings)
3. [Boot the ISO, network, clock](#3-boot-the-iso-network-clock)
4. [Partitioning](#4-partitioning)
5. [LUKS2](#5-luks2)
6. [btrfs subvolumes and mounts](#6-btrfs-subvolumes-and-mounts)
7. [pacstrap](#7-pacstrap)
8. [fstab](#8-fstab)
9. [chroot: locale, time, users, sudo](#9-chroot-locale-time-users-sudo)
10. [CachyOS x86-64-v4 repositories](#10-cachyos-x86-64-v4-repositories)
11. [Network](#11-network)
12. [Swap: zram + swapfile](#12-swap-zram--swapfile)
13. [initramfs and UKI](#13-initramfs-and-uki)
14. [Kernel command line, parameter by parameter](#14-kernel-command-line-parameter-by-parameter)
15. [Boot entries: UKI straight from firmware](#15-boot-entries-uki-straight-from-firmware)
16. [First boot](#16-first-boot)
17. [Secure Boot with sbctl](#17-secure-boot-with-sbctl)
18. [TPM2 auto-unlock](#18-tpm2-auto-unlock)
19. [Fallback GRUB (optional)](#19-fallback-grub-optional)
20. [Switching to the custom kernel](#20-switching-to-the-custom-kernel)
21. [Boot chain optimisations in effect](#21-boot-chain-optimisations-in-effect)
22. [Troubleshooting](#22-troubleshooting)

---

## 1. Final layout

```
nvme0n1               953.9G  GPT
├─nvme0n1p1             1G    EFI System (vfat)        -> /boot
└─nvme0n1p2           952.9G  Linux root x86-64, LUKS2 -> /dev/mapper/root
  └─root                      btrfs
      @        -> /
      @home    -> /home
      @pkg     -> /var/cache/pacman/pkg
      @log     -> /var/log
      @swap    -> /swap  (swapfile, no compression)
zram0                   4G    swap, zstd, priority 100
```

Boot chain:

```
UEFI firmware (Secure Boot: own keys + Microsoft keys)
  └─ Boot0003  \EFI\Linux\arch-linux-lapidary.efi   (UKI, signed with sbctl)   default
     Boot0002  \EFI\Linux\arch-linux.efi            (stock Arch kernel UKI)    fallback
     Boot0004  \EFI\grub-fallback\grubx64.efi       (signed standalone GRUB)  optional menu
       └─ systemd-stub -> kernel -> systemd initramfs
            └─ sd-encrypt: TPM2 (PCR 7) unlocks root, passphrase as fallback
```

There is no boot loader in the normal path. The firmware loads the UKI directly; the
kernel command line, initramfs, microcode and splash image are all inside the signed UKI.

## 2. Before you start: firmware settings

Enter the firmware setup with **F2** at power-on; **ESC** opens the one-time boot
menu. The ASUS setup has an "EZ mode" and an "Advanced mode" (F7). Menu names below
may differ slightly between BIOS versions.

| Setting | During install | Final state | Why |
|---|---|---|---|
| Secure Boot | **Disabled** | Enabled, own keys + Microsoft keys (section 17) | The Arch ISO is not signed. Keys are enrolled once the system boots. |
| TPM (firmware TPM, `MSFT0101`) | Enabled (default) | Enabled | Needed for TPM2 auto-unlock. |
| Boot order | USB first | Managed with `efibootmgr` | |

Update the BIOS first if you can (EZ Flash in the firmware setup reads the update from a
FAT32 USB stick). A firmware update changes TPM measurements; doing it before you set up
TPM unlock avoids having to re-enroll.

GPU MUX: the reference machine runs in the default Optimus/hybrid mode
(`gpu_mux_mode=1`, iGPU drives the panel). Nothing in this guide assumes dGPU-only mode;
see [docs/03](03-g14-hardware-and-power.md) for GPU switching.

Check the current state from any Linux system:

```sh
sbctl status          # Setup Mode / Secure Boot / Vendor Keys
bootctl status        # firmware, Secure Boot, TPM2 support, measured UKI
```

On the finished system they report:

```
Setup Mode:  Disabled
Secure Boot: Enabled
Vendor Keys: microsoft

Secure Boot: enabled (user)
TPM2 Support: yes
Measured UKI: yes
```

## 3. Boot the ISO, network, clock

Write the current Arch ISO to a USB stick, boot it from the ESC menu.

The 2880x1800 panel makes the console font tiny. Use a larger one and set your keymap
(Turkish Q shown as an example):

```sh
setfont ter-132b
loadkeys trq          # list: localectl list-keymaps
```

Confirm UEFI mode (must print `64`):

```sh
cat /sys/firmware/efi/fw_platform_size
```

Wi-Fi (Intel AX210, works out of the box) with `iwctl`:

```sh
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect "<SSID>"
[iwd]# exit
ping -c 3 archlinux.org
```

Clock (NTP is on by default in the ISO; just check it is synchronised):

```sh
timedatectl
```

## 4. Partitioning

**What:** GPT with a 1 GiB ESP and one LUKS2 partition for everything else.

**Why:** the ESP is mounted at `/boot` and holds the UKIs directly. Each UKI is about
95 MB here (two kernels plus the fallback GRUB use about 230 MB), so 1 GiB leaves room
for a third kernel or a temporarily larger image. No separate swap partition: swap is a
file inside the encrypted btrfs plus zram. Partition type `8304` (Linux root x86-64)
marks the LUKS partition as the root for discoverable-partition tooling.

**How** (this wipes the disk):

```sh
lsblk                                   # make sure nvme0n1 is the right disk
sgdisk --zap-all /dev/nvme0n1
sgdisk -n1:0:+1G -t1:ef00 \
       -n2:0:0   -t2:8304 /dev/nvme0n1
mkfs.fat -F 32 /dev/nvme0n1p1
```

**Verify:** `lsblk -o NAME,SIZE,PARTTYPENAME /dev/nvme0n1` shows "EFI System" and
"Linux root (x86-64)".

## 5. LUKS2

**What:** LUKS2 on `nvme0n1p2`, opened as `/dev/mapper/root`.

The header on the reference machine (from `cryptsetup luksDump`, identifiers omitted):

| Parameter | Value | Note |
|---|---|---|
| Version | LUKS2 | |
| Cipher | `aes-xts-plain64`, 512-bit key | cryptsetup default |
| Sector size | 512 bytes | The KIOXIA BG6 reports 512 B logical and physical blocks; cryptsetup picks 4096 automatically on 4K drives. |
| Passphrase keyslot PBKDF | argon2id, about 1 GiB memory, 4 threads | default; time cost is benchmarked at format time |
| Data offset | 16 MiB | default |
| Flags | `allow-discards` | see below |
| Keyslots | passphrase, recovery key, TPM2 | sections 18 |

The defaults are what you want; there is no need to pass cipher options:

```sh
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
cryptsetup open --allow-discards --persistent /dev/nvme0n1p2 root
```

`--allow-discards --persistent` stores the discard flag in the LUKS2 header, so TRIM
reaches the SSD without any crypttab or kernel option. **Trade-off:** discards reveal
which blocks are unused (how full the disk is, roughly where data lives). On a laptop
SSD the endurance and performance benefit was considered worth it. To turn it on later
on an already open volume: `cryptsetup refresh root --allow-discards --persistent`.

**Verify:** `cryptsetup status root` shows `flags: discards`;
`cryptsetup luksDump /dev/nvme0n1p2 | grep Flags` shows `allow-discards`.

Pick a strong passphrase. It stays in keyslot 0 forever; the TPM is only a convenience
on top of it.

## 6. btrfs subvolumes and mounts

**What:** one btrfs filesystem with five top-level subvolumes.

| Subvolume | Mount point | Why separate |
|---|---|---|
| `@` | `/` | snapshotted by snapper (root config) |
| `@home` | `/home` | own snapper config; rolling back `/` must not touch user data |
| `@pkg` | `/var/cache/pacman/pkg` | package cache is large and reproducible; kept out of root snapshots |
| `@log` | `/var/log` | logs must survive a root rollback (you want the logs of the broken state) |
| `@swap` | `/swap` | a swapfile cannot live in a subvolume that gets snapshotted; mounted without compression |

Mount options (from the live `/etc/fstab`):
`rw,noatime,compress=zstd:3,ssd,space_cache=v2` for all data subvolumes and
`rw,noatime,ssd,space_cache=v2` (no `compress`) for `@swap`.

- `noatime`: no metadata write on every read; matters with CoW and snapshots.
- `compress=zstd:3`: transparent compression, cheap on this CPU.
- `ssd`, `space_cache=v2`: what btrfs picks anyway on NVMe; written out explicitly.
- The kernel also enables `discard=async` by default on SSDs (visible in `findmnt -no
  OPTIONS /`), and `fstrim.timer` runs weekly on top of it.

```sh
mkfs.btrfs /dev/mapper/root
mount /dev/mapper/root /mnt
for sv in @ @home @pkg @log @swap; do btrfs subvolume create /mnt/$sv; done
umount /mnt

o=rw,noatime,compress=zstd:3,ssd,space_cache=v2
mount -o $o,subvol=/@ /dev/mapper/root /mnt
mount --mkdir -o $o,subvol=/@home /dev/mapper/root /mnt/home
mount --mkdir -o $o,subvol=/@pkg  /dev/mapper/root /mnt/var/cache/pacman/pkg
mount --mkdir -o $o,subvol=/@log  /dev/mapper/root /mnt/var/log
mount --mkdir -o rw,noatime,ssd,space_cache=v2,subvol=/@swap /dev/mapper/root /mnt/swap
mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

`fmask=0077,dmask=0077` on the ESP keeps `/boot/loader/random-seed` and the UKIs
readable only by root (bootctl warns otherwise).

## 7. pacstrap

**What:** the minimal set needed to boot this layout and get online. Everything else
(desktop, apps) comes from [`packages/`](../packages) after the first boot.

```sh
pacstrap -K /mnt \
  base base-devel linux linux-headers linux-firmware amd-ucode sof-firmware \
  mkinitcpio btrfs-progs dosfstools exfatprogs \
  efibootmgr sbctl tpm2-tss \
  networkmanager wpa_supplicant wireless-regdb \
  zram-generator sudo git man-db micro nano fish
```

Why each non-obvious one is there:

| Package | Why |
|---|---|
| `linux`, `linux-headers` | stock Arch kernel; stays installed as the fallback UKI even after you switch to a custom kernel. Headers are for `nvidia-open-dkms`. |
| `amd-ucode` | CPU microcode; the `microcode` mkinitcpio hook embeds it in the UKI. |
| `sof-firmware` | firmware for the AMD audio coprocessor (ACP) path; harmless if unused. |
| `sbctl` | creates and enrolls Secure Boot keys and signs UKIs (pacman/mkinitcpio hooks re-sign automatically). |
| `tpm2-tss` | only an *optional* dependency of systemd, but `systemd-cryptenroll --tpm2-device` and TPM unlock in the initramfs need it. |
| `zram-generator` | creates `/dev/zram0` from `/etc/systemd/zram-generator.conf`. |
| `wireless-regdb` | correct Wi-Fi regulatory domain (set `WIRELESS_REGDOM` in `/etc/conf.d/wireless-regdom`). |

`cryptsetup` is pulled in by `systemd` already. Pick your own editor and shell; `micro`
and `fish` are just what the reference machine uses.

The repos are still the stock Arch ones at this point. They are switched to CachyOS
v4 builds in section 10.

## 8. fstab

```sh
genfstab -U /mnt >> /mnt/etc/fstab
```

Compare the result with [`system/etc/fstab`](../system/etc/fstab) and fix two things
`genfstab` gets wrong for this layout:

- `genfstab` writes `subvolid=` next to `subvol=`. Remove `subvolid=...`: IDs change
  when a snapshot is restored, the name does not.
- Add the swapfile line after creating the file in section 12:
  `/swap/swapfile  none  swap  defaults,pri=10  0 0`

Template:

```
UUID=<ROOT-FS-UUID>  /                      btrfs  rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@      0 0
UUID=<ROOT-FS-UUID>  /home                  btrfs  rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@home  0 0
UUID=<ROOT-FS-UUID>  /var/cache/pacman/pkg  btrfs  rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@pkg   0 0
UUID=<ROOT-FS-UUID>  /var/log               btrfs  rw,noatime,compress=zstd:3,ssd,space_cache=v2,subvol=/@log   0 0
UUID=<ESP-UUID>      /boot                  vfat   rw,relatime,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro  0 2
UUID=<ROOT-FS-UUID>  /swap                  btrfs  rw,noatime,ssd,space_cache=v2,subvol=/@swap                  0 0
/swap/swapfile       none                   swap   defaults,pri=10                                              0 0
```

`<ROOT-FS-UUID>` is the btrfs UUID (`blkid -s UUID -o value /dev/mapper/root`), not the
LUKS UUID.

## 9. chroot: locale, time, users, sudo

```sh
arch-chroot /mnt
```

**Time zone.** The reference machine uses `Europe/Istanbul`; pick yours
(`timedatectl list-timezones`):

```sh
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd
```

**Locale.** English UI with a second locale available. Uncomment the ones you want in
`/etc/locale.gen` (here `en_US.UTF-8 UTF-8` and `tr_TR.UTF-8 UTF-8`), then:

```sh
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
```

**Console keymap** - [`system/etc/vconsole.conf`](../system/etc/vconsole.conf) is an
example for a Turkish Q keyboard; the `sd-vconsole` initramfs hook copies it into the
UKI so the LUKS passphrase prompt uses the same layout:

```
KEYMAP=trq
FONT=default8x16
XKBLAYOUT=tr
XKBMODEL=pc105
XKBOPTIONS=terminate:ctrl_alt_bksp
```

**Hostname:**

```sh
echo '<hostname>' > /etc/hostname
```

`/etc/hosts` only needs the two default `localhost` lines; systemd-resolved
(`nss-myhostname`) resolves the machine's own name.

**Users and sudo:**

```sh
passwd                                   # root password
useradd -m -G wheel -s /usr/bin/fish <user>
passwd <user>
install -m 0440 /dev/stdin /etc/sudoers.d/10-wheel <<< '%wheel ALL=(ALL:ALL) ALL'
visudo -c
```

(Same content as [`system/etc/sudoers.d/10-wheel`](../system/etc/sudoers.d/10-wheel).)
Extra groups used later: `input` (some input tools), `libvirt` and `kvm` (virtual
machines). The reference machine also has a `NOPASSWD` rule for its user; that is a
convenience with an obvious security cost and is not recommended.

## 10. CachyOS x86-64-v4 repositories

**What:** CachyOS's repositories rebuild most of Arch's packages for newer x86-64
micro-architecture levels. This system uses the **v4** repos (`cachyos-v4`,
`cachyos-core-v4`, `cachyos-extra-v4`) plus the generic `cachyos` repo, ahead of the
Arch repos. Most of the installed packages come from them (on the reference machine:
about 1100 from `cachyos-extra-v4`, about 140 from `cachyos-core-v4`, plus a few dozen
from `cachyos-v4` and `cachyos`).

**Why v4 works here:** x86-64-v4 is the v3 baseline (AVX2, BMI2, FMA, ...) plus AVX-512
F, BW, CD, DQ and VL. Zen 5 implements all of them (`lscpu` lists `avx512f avx512dq
avx512cd avx512bw avx512vl`, plus `avx512_vnni`, `avx512_bf16`). glibc confirms it:

```sh
/usr/lib/ld-linux-x86-64.so.2 --help | grep x86-64-v
#  x86-64-v4 (supported, searched)
#  x86-64-v3 (supported, searched)
#  x86-64-v2 (supported, searched)
```

If your CPU does not print "x86-64-v4 (supported...)", use the v3 repos instead. Never
enable v4 repos on a CPU without AVX-512: binaries die with "illegal instruction".

The CachyOS repos also ship their own `pacman` build. It understands
`Architecture = auto` and resolves it to `x86_64 x86_64_v2 x86_64_v3 x86_64_v4`
(`pacman-conf Architecture`), which is what lets pacman accept `x86_64_v4` packages.

**How (recommended):** CachyOS's own installer script. It checks the CPU level,
imports and locally signs the CachyOS key, installs `cachyos-keyring`, the mirrorlists
and CachyOS `pacman`, and adds the repo blocks to `/etc/pacman.conf`:

```sh
curl -LO https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
less cachyos-repo.sh          # read it before running it
./cachyos-repo.sh
```

**How (manual):** the same steps by hand. Check the current file names on
`https://mirror.cachyos.org/repo/x86_64/cachyos/` first, they change with each release.

```sh
pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
pacman-key --lsign-key F3B607488DB35A47
pacman -U 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-<ver>-any.pkg.tar.zst' \
          'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-<ver>-any.pkg.tar.zst' \
          'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-<ver>-any.pkg.tar.zst' \
          'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-<ver>-any.pkg.tar.zst' \
          'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-<ver>-x86_64.pkg.tar.zst'
```

Then put the CachyOS blocks **above** `[core]` in `/etc/pacman.conf` (order matters:
the first repo that has a package wins) and set `Architecture = auto`. The reference
file is [`system/etc/pacman.conf`](../system/etc/pacman.conf); the relevant part:

```ini
[options]
Architecture = auto
Color
CheckSpace
ParallelDownloads = 5
DownloadUser = alpm
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
```

`multilib` is needed for Steam/Wine 32-bit libraries.

Now refresh and upgrade. CachyOS rebuilds carry a higher `pkgrel` (for example
`5.3.3-2.1`), so a normal upgrade replaces the Arch builds with the v4 ones:

```sh
pacman -Syyu
```

**Verify:** `pacman -Qi bash | grep -E 'Packager|Architecture'` shows CachyOS and
`x86_64_v4`; `pacman -Sl cachyos-core-v4 | grep -c installed` is non-zero.

**Revert:** remove the four CachyOS blocks from `pacman.conf`, `pacman -Syyuu` (the
double `u` downgrades back to Arch's builds), then remove `cachyos-*mirrorlist` and
`cachyos-keyring`. Do not remove the repos while CachyOS-only packages (for example
`cachy-update`, see [02-desktop.md](02-desktop.md)) are still installed.

## 11. Network

**What:** NetworkManager (with `wpa_supplicant` as its Wi-Fi backend) for links, and
systemd-resolved for DNS.

```sh
systemctl enable NetworkManager systemd-resolved
```

After the first boot (inside `arch-chroot` the file is bind-mounted and cannot be
replaced), point `resolv.conf` at the resolved stub:

```sh
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

Optional, as on the reference machine: a single fixed resolver with DNS over TLS for
every connection. NetworkManager is told to stay out of DNS entirely, so DHCP-provided
resolvers are never used:

- [`system/etc/NetworkManager/conf.d/10-dns-none.conf`](../system/etc/NetworkManager/conf.d/10-dns-none.conf):
  `dns=none`, `rc-manager=unmanaged`
- [`system/etc/systemd/resolved.conf.d/10-dot.conf`](../system/etc/systemd/resolved.conf.d/10-dot.conf):
  `DNS=1.1.1.1`, `DNSOverTLS=yes`, `Domains=~.`, empty `FallbackDNS`, LLMNR and mDNS off.

The trade-off: captive portals (hotel/airport Wi-Fi) and split-horizon corporate DNS do
not work while this is active. Revert by deleting both files and
`systemctl restart systemd-resolved NetworkManager`.

**Verify:** `resolvectl status` shows `+DNSOverTLS` and `Current DNS Server: 1.1.1.1`
on the global section.

Wi-Fi regulatory domain: set yours in `/etc/conf.d/wireless-regdom`
(`WIRELESS_REGDOM="TR"` on the reference machine).

## 12. Swap: zram + swapfile

**What:** two swap devices with different priorities:

| Device | Size | Priority | Role |
|---|---|---|---|
| `/dev/zram0` | 4 GiB (zram-generator default: min(RAM/2, 4 GiB)) | 100 | compressed RAM swap, used first |
| `/swap/swapfile` | 34 GiB | 10 | overflow on disk (inside LUKS) |

**Why:** zram absorbs normal memory pressure without touching the SSD; the swapfile is
a safety net. The swapfile was sized for hibernation (RAM + margin), but hibernation is
**masked** on this machine because resume is unreliable on this platform (see [docs/03](03-g14-hardware-and-power.md)
on sleep). s2idle draws about 0.2-0.6 W (measured on this machine), so suspend is used instead. If you do not plan to
experiment with hibernation, a 4-8 GiB swapfile is plenty.

zram config, [`system/etc/systemd/zram-generator.conf`](../system/etc/systemd/zram-generator.conf):

```ini
[zram0]
compression-algorithm = zstd
```

Swapfile on the uncompressed `@swap` subvolume (`btrfs filesystem mkswapfile` sets
NOCOW and preallocates):

```sh
btrfs filesystem mkswapfile --size 34g /swap/swapfile
echo '/swap/swapfile none swap defaults,pri=10 0 0' >> /etc/fstab
```

zswap must be **off** when zram is used, otherwise pages are compressed twice (once in
zswap, then again in zram). Both the stock Arch kernel and the CachyOS-based custom
kernel enable zswap by default (`CONFIG_ZSWAP_DEFAULT_ON=y`), hence
`zswap.enabled=0` on the command line (section 14).

**Verify** (after boot): `swapon --show` lists `/dev/zram0` with PRIO 100 and the
swapfile with PRIO 10; `cat /sys/module/zswap/parameters/enabled` prints `N`.

## 13. initramfs and UKI

**What:** a systemd-based initramfs, bundled together with the kernel, microcode,
command line and a splash image into one UKI per kernel. `mkinitcpio` builds the UKI
itself using systemd's EFI stub (`/usr/lib/systemd/boot/efi/linuxx64.efi.stub`);
`ukify` is not used.

### mkinitcpio.conf

[`system/etc/mkinitcpio.conf`](../system/etc/mkinitcpio.conf):

```sh
MODULES=()
BINARIES=()
FILES=(/usr/lib/firmware/edid/g14-hdr.bin)
HOOKS=(base systemd plymouth autodetect microcode modconf amdkms keyboard sd-vconsole block sd-encrypt filesystems fsck)
COMPRESSION="zstd"
```

| Item | Why |
|---|---|
| `systemd` instead of `udev` | required for `sd-encrypt`, TPM2 unlock and credential handling. |
| `plymouth` | boot splash; needs the `plymouth` package (the reference machine uses a patched build, see [04-custom-packages.md](04-custom-packages.md)). Leave it out until Plymouth is installed. |
| `microcode` | embeds `amd-ucode` early in the UKI (no separate `amd-ucode.img` to load). |
| `amdkms` (local hook) instead of `kms` | see below. |
| `sd-vconsole` | keymap for the passphrase prompt. |
| `sd-encrypt` | unlocks root from `/etc/crypttab` lines marked `x-initrd.attach`. |
| `MODULES=()` | nothing force-loaded, see below. |
| `FILES=(... g14-hdr.bin)` | **[GA403GM]** patched EDID for HDR, loaded by `drm.edid_firmware=` at boot, so it must be inside the image. Created in [docs/03](03-g14-hardware-and-power.md). **Remove this line until that file exists**, or mkinitcpio fails. |

**The `amdkms` hook.** The stock `kms` hook adds every GPU driver that matches a device
on the PCI bus. When the NVIDIA dGPU is visible, that includes `nouveau`, and `nouveau`
pulls in every NVIDIA GSP firmware blob: about 146 MiB, making the UKI 207 MB instead of
95 MB. `nouveau` is blacklisted anyway (the proprietary/open NVIDIA driver is used), so
that firmware is dead weight. The replacement hook only adds `amdgpu`:

[`system/etc/initcpio/install/amdkms`](../system/etc/initcpio/install/amdkms):

```bash
#!/bin/bash
build() { add_module amdgpu; }
help() { echo "Adds the amdgpu driver and its firmware to the initramfs without forcing it to load."; }
```

`amdgpu` is deliberately **not** in `MODULES=()`. Listing it there makes
`systemd-modules-load` load it synchronously, and the LUKS/TPM unlock waits behind it:
measured on this machine, initrd took 3.74 s with `MODULES=(amdgpu)` and 2.44 s with the
hook (udev loads amdgpu in parallel; early KMS and the Plymouth splash still work).

NVIDIA modules are not in the initramfs either; the panel is driven by the iGPU and the
dGPU driver loads later from the root filesystem.

```sh
install -Dm644 system/etc/mkinitcpio.conf /etc/mkinitcpio.conf
install -Dm644 system/etc/initcpio/install/amdkms /etc/initcpio/install/amdkms
```

### Presets

[`system/etc/mkinitcpio.d/linux.preset`](../system/etc/mkinitcpio.d/linux.preset)
(the important lines):

```sh
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options="--splash /boot/splash.bmp"
```

- Only the `default` preset is built: no fallback image per kernel. The second kernel
  (stock `linux` next to the custom one) is the fallback, and it saves ~95 MB of ESP.
- `default_image` is not set, so no separate `initramfs-*.img` is written; only the UKI.
- `--splash /boot/splash.bmp` is optional: a 2880x1800 24-bit BMP that systemd-stub
  shows before the kernel starts. Drop the option if you do not have one. Any image
  works, for example: `magick logo.png -background black -gravity center -extent
  2880x1800 -type TrueColor BMP3:/boot/splash.bmp`.

The custom kernel's preset is
[`system/etc/mkinitcpio.d/linux-lapidary.preset`](../system/etc/mkinitcpio.d/linux-lapidary.preset),
same shape, writing `/boot/EFI/Linux/arch-linux-lapidary.efi`.

### crypttab

[`system/etc/crypttab`](../system/etc/crypttab):

```
root  UUID=<LUKS-UUID>  none  tpm2-device=auto,x-initrd.attach
```

- `<LUKS-UUID>`: `blkid -s UUID -o value /dev/nvme0n1p2` (the LUKS partition).
- `x-initrd.attach`: `sd-encrypt` copies this line into the initramfs. This replaces the
  older `/etc/crypttab.initramfs` file (mkinitcpio 42 warns about that file).
- `tpm2-device=auto`: try the TPM2 token first, then ask for the passphrase.
  Until a TPM2 keyslot is enrolled (section 18) it simply asks for the passphrase.
- No `discard` option: the flag lives in the LUKS2 header (section 5).

### Kernel command line

[`system/etc/kernel/cmdline`](../system/etc/kernel/cmdline) is embedded into every UKI.
For the first boot with the stock kernel, start with the minimal version:

```
root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs zswap.enabled=0
```

and add the rest as you go through [docs/03](03-g14-hardware-and-power.md) and [docs/04](04-custom-packages.md). Section 14 explains
the full line.

### Build

```sh
mkdir -p /boot/EFI/Linux
mkinitcpio -P
ls -lh /boot/EFI/Linux/
```

**Verify:** `arch-linux.efi` exists (about 95 MB with this config; much larger means
the NVIDIA firmware got in - check you are using `amdkms`, not `kms`). Inspect with
`lsinitcpio -a /boot/EFI/Linux/arch-linux.efi` or `ukify inspect` if you have
`systemd-ukify`.

**Revert:** put `kms` back in place of `amdkms` and rebuild with `mkinitcpio -P`.

## 14. Kernel command line, parameter by parameter

The live `/etc/kernel/cmdline` (identical to `/proc/cmdline`):

```
splash nvidia_drm.modeset=1 root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs drm.edid_firmware=eDP-1:edid/g14-hdr.bin loglevel=6 rcu_nocbs=all rcutree.enable_rcu_lazy=1
```

| Parameter | What it does | Why here |
|---|---|---|
| `root=/dev/mapper/root` | root device | the mapping opened by `sd-encrypt` from crypttab; no `rd.luks.*` options needed because crypttab is in the initramfs. |
| `rootflags=subvol=@` | mount subvolume `@` as `/` | layout from section 6. By name, not ID. |
| `rw` | mount root read-write directly | no separate remount step; `fsck` is a no-op for btrfs anyway. |
| `rootfstype=btrfs` | skip filesystem probing | small speed-up, avoids probing surprises. |
| `zswap.enabled=0` | disable zswap | zram is used instead (section 12); avoids double compression. |
| `splash` | tell Plymouth to show the splash | only useful with the `plymouth` hook. |
| `loglevel=6` | console log level INFO | the Plymouth theme used here prints kernel messages on the splash, and without it INFO lines are filtered out. With a stock Plymouth theme, use `quiet` instead and drop `loglevel=6`. See [04-custom-packages.md](04-custom-packages.md). |
| `nvidia_drm.modeset=1` | NVIDIA DRM KMS | required for Wayland on the dGPU. Current NVIDIA drivers default to it and `/etc/modprobe.d/nvidia.conf` sets it too; kept on the command line as a belt-and-braces setting. |
| `drm.edid_firmware=eDP-1:edid/g14-hdr.bin` | override the internal panel's EDID | **[GA403GM]** makes the OLED panel's HDR capability visible to KWin. The file must be in the UKI (`FILES=` above). See [docs/03](03-g14-hardware-and-power.md). Leave it out if you do not use the override. |
| `rcu_nocbs=all` | move RCU callback processing off all CPUs into kthreads | prerequisite for lazy RCU. |
| `rcutree.enable_rcu_lazy=1` | batch non-urgent RCU callbacks | fewer timer wakeups at idle: measured on this machine about 0.1 W lower idle package power (local timer interrupts roughly halved), no measurable effect during video playback. Needs `CONFIG_RCU_LAZY=y` (`zgrep RCU_LAZY /proc/config.gz`). |

Under Secure Boot, systemd-stub ignores any command line passed from outside the UKI.
To boot with a different command line you need a separately built UKI (or a UKI
profile); editing a boot entry does nothing. After changing `/etc/kernel/cmdline`, run
`mkinitcpio -P`; sbctl's post hook re-signs the new images.

## 15. Boot entries: UKI straight from firmware

**What:** NVRAM boot entries that point the firmware directly at the UKI files. No
systemd-boot, no GRUB in the normal path.

**Why:** one less stage to keep signed and updated, about 0.4 s loader time, and nothing
between the firmware and the measured UKI. The firmware's own boot menu (ESC) is the
fallback menu; it lists every entry below.

```sh
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
  --label "Arch Linux" --loader '\EFI\Linux\arch-linux.efi'
```

After installing the custom kernel (section 20) add its entry and make it the default:

```sh
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
  --label "Arch Linux (lapidary)" --loader '\EFI\Linux\arch-linux-lapidary.efi'
efibootmgr                         # note the new Boot#### numbers
efibootmgr --bootorder 0003,0002,0004   # custom UKI, stock UKI, fallback GRUB
efibootmgr --timeout 1
```

The live result (`efibootmgr`, device paths shortened):

```
BootCurrent: 0003
Timeout: 1 seconds
BootOrder: 0003,0002,0004,000C,000D,000E,000F
Boot0002* Arch Linux              HD(1,GPT,<ESP-PARTUUID>,...)/\EFI\Linux\arch-linux.efi
Boot0003* Arch Linux (lapidary)   HD(1,GPT,<ESP-PARTUUID>,...)/\EFI\Linux\arch-linux-lapidary.efi
Boot0004* GRUB (fallback)         HD(1,GPT,<ESP-PARTUUID>,...)/\EFI\grub-fallback\grubx64.efi
Boot000C* UEFI OS                 HD(1,GPT,<ESP-PARTUUID>,...)/\EFI\BOOT\BOOTX64.EFI
Boot000D* UEFI:CD/DVD Drive
Boot000E* UEFI:Removable Device
Boot000F* UEFI:Network Device
```

`Boot000C` is the firmware's generic removable-media path; on the reference machine
`\EFI\BOOT\BOOTX64.EFI` is a leftover from an earlier install and is not part of this
setup. If you want a safety net for when NVRAM gets reset, copy the stock UKI there
(`cp /boot/EFI/Linux/arch-linux.efi /boot/EFI/BOOT/BOOTX64.EFI` and
`sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI`), but remember it does not update itself.

Do **not** delete `/boot/loader/`: even without systemd-boot, the stub inside the UKI
uses `/boot/loader/random-seed`, `/boot/loader/credentials/` and the
`boot-secret-mixin` file. `systemd-boot-update.service` is masked on the reference
machine because there is no systemd-boot to update.

**Verify:** `bootctl status` shows `Stub: └─/EFI/Linux/arch-linux-lapidary.efi` under
"Current Stub" and the BootOrder is as above.

**Revert / add a menu:** `bootctl install`, sign `/boot/EFI/systemd/systemd-bootx64.efi`
with `sbctl sign -s`, and put the "Linux Boot Manager" entry first. systemd-boot finds
UKIs in `/boot/EFI/Linux` automatically.

## 16. First boot

```sh
exit                          # leave the chroot
umount -R /mnt
cryptsetup close root
reboot
```

You are asked for the LUKS passphrase (no TPM yet), then get a text login. Log in as
your user and check:

```sh
systemctl --failed
swapon --show
findmnt -t btrfs,vfat
```

Then continue with the desktop in [02-desktop.md](02-desktop.md). Secure Boot and TPM
can be done now or after the desktop; they must be done in the order below (Secure Boot
first), because the TPM policy is bound to the Secure Boot state.

## 17. Secure Boot with sbctl

**What:** your own Platform Key / KEK / db keys, enrolled **together with Microsoft's
keys**, and every EFI binary on the ESP signed with them.

**Why own keys:** there is no shim and no distribution signature in this chain; the
UKIs are built locally and need a key you control. **Why keep Microsoft's keys
(`-m`):** firmware drivers and option ROMs (for example on the dGPU) are signed with
Microsoft's UEFI CA. Enrolling without them can leave a laptop without display output
in the firmware. `sbctl status` on the reference machine reports
`Vendor Keys: microsoft`.

**How:**

1. Firmware setup (F2) -> Security -> Secure Boot -> key management: clear/delete the
   Secure Boot keys. This puts the firmware into **Setup Mode**. Boot Linux.
2. Check and enroll:

   ```sh
   sbctl status                 # must say: Setup Mode: Enabled
   sbctl create-keys
   sbctl enroll-keys -m         # -m = also enroll Microsoft's keys
   ```

3. Sign and register every binary the firmware will load (`-s` saves the path in
   `/var/lib/sbctl/files.json`, so they are re-signed automatically later):

   ```sh
   sbctl sign -s /boot/EFI/Linux/arch-linux.efi
   sbctl sign -s /boot/EFI/Linux/arch-linux-lapidary.efi     # once the custom kernel exists
   sbctl verify
   ```

4. Reboot into the firmware setup, enable Secure Boot, save.

Automatic re-signing is done by two hooks shipped with `sbctl`: the mkinitcpio post
hook (`/usr/lib/initcpio/post/sbctl`) signs a UKI right after it is built, and the
pacman hook (`zz-sbctl.hook`, runs `sbctl sign-all -g`) re-signs everything in the
database after any transaction that touches `/boot` or EFI files. Kernel updates need
no manual step.

**Verify:** `sbctl status` -> `Secure Boot: Enabled`, `Setup Mode: Disabled`;
`sbctl list-files` shows every file as `Signed`; `bootctl status` -> `Secure Boot:
enabled (user)`.

**Revert:** disable Secure Boot in the firmware. The keys can stay enrolled. (If you
had TPM unlock enrolled, it now falls back to the passphrase, see section 18.)

## 18. TPM2 auto-unlock

**What:** a TPM2 keyslot that releases the LUKS key only when PCR 7 matches, plus a
recovery key. The passphrase keyslot stays.

Keyslots on the reference machine:

| Keyslot | Token | Purpose |
|---|---|---|
| 0 | - | passphrase (argon2id). Never remove it. |
| 1 | `systemd-recovery` | recovery key (high-entropy, pbkdf2) |
| 3 | `systemd-tpm2` | TPM2, `tpm2-hash-pcrs: 7`, `tpm2-pcr-bank: sha256`, no PIN, no pcrlock, no signed policy, SRK enabled |

**Why only PCR 7:** PCR 7 records the Secure Boot state and the certificates that
authorised what was booted (your own db key for these UKIs). If Secure Boot is turned
off, the keys are changed, or something signed by a different authority is booted, the
TPM refuses and you get the passphrase prompt. Other PCRs were left out on purpose:

- PCR 0/2 (firmware code, option ROMs) change with every BIOS update.
- PCR 4 (boot loader / UKI hash) and PCR 11 (UKI sections) change with every kernel or
  initramfs rebuild; binding to them would need `systemd-pcrlock` or a signed PCR
  policy to avoid typing the passphrase after every update.

The trade-off: anyone who can boot an image signed with *your* key gets the same
PCR 7. Keep the sbctl keys (`/var/lib/sbctl/keys`) on the encrypted root only, and keep
the fallback GRUB's command line disabled (section 19).

**How** (as root, with Secure Boot already enabled):

```sh
systemd-cryptenroll /dev/nvme0n1p2 --recovery-key        # prints a key: store it offline
systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=7
```

Both commands ask for the existing passphrase. Nothing else changes: crypttab already
has `tpm2-device=auto` (section 13), so the next boot unlocks without a prompt.

**Verify:** `cryptsetup luksDump /dev/nvme0n1p2` lists `systemd-tpm2` with
`tpm2-hash-pcrs: 7`; reboot and `journalctl -b -u systemd-cryptsetup@root` shows the
volume unlocked via TPM2.

**Re-enroll** (when the passphrase prompt comes back after a firmware change):

```sh
systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7
```

Known triggers, in the order to check them:

1. Secure Boot got disabled (`sbctl status`). Turning it back on fixes it, no
   re-enrollment needed.
2. A systemd update changed what gets measured. Since systemd 261.3,
   `systemd-pcrosseparator.service` extends an "os-separator" event into PCR 0-7, 9 and
   12-14 in the initrd *before* cryptsetup runs. A slot enrolled before that version
   no longer matches; re-enroll once and it is stable again. (Check with
   `journalctl -b | grep -i separator`.)
3. BIOS update or Secure Boot key changes.

**Revert:** `systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=tpm2`.

## 19. Fallback GRUB (optional)

**What:** a standalone, signed GRUB at `\EFI\grub-fallback\grubx64.efi` with a fixed
menu that chainloads the two UKIs, plus firmware setup / reboot / power off. It is never
in the normal boot path; you pick it from the ESC menu or with
`efibootmgr --bootnext 0004`.

**Why:** a readable menu without relying on the firmware's boot menu, kept small and
locked down. Sources: [`system/grub-fallback/`](../system/grub-fallback)
(`grub.cfg`, `theme/theme.txt`, `build.sh`).

Design points (all explained in `build.sh`):

- **Chainload only.** Entries hand the UKI to the firmware's `LoadImage()`, so the
  firmware checks the signature and PCR 7 is the same as for a direct UKI boot: TPM
  unlock keeps working. GRUB's `linux`/`initrd` commands are not used (the UKI's
  command line could not be changed under Secure Boot anyway).
- **Everything in memdisk.** `grub-mkstandalone` packs modules, `grub.cfg`, fonts and
  theme into the single signed binary. Memdisk files are exempt from GRUB's verifiers,
  so the font and theme load under Secure Boot lockdown.
- **`--disable-shim-lock`, no SBAT.** There is no shim in this chain.
- **The `tpm` module is mandatory.** Under lockdown GRUB marks chainloaded images
  "defer auth"; without shim, the only verifier that accepts them is the TPM one. With
  the TPM disabled in firmware the GRUB entries fail (direct UKI boot is unaffected).
- **`--disable-cli`.** The TPM verifier also accepts unsigned modules from disk; with an
  editable menu or command line, anyone at the keyboard could load arbitrary code
  without changing PCR 7, and PCR 7 is all the LUKS TPM slot checks. With the CLI
  disabled, every entry must be `--unrestricted`.

**How** (needs `grub`, `imagemagick`, `ttf-jetbrains-mono`):

```sh
cd system/grub-fallback
sed -i "s/<ESP-UUID>/$(blkid -s UUID -o value /dev/nvme0n1p1)/" grub.cfg
./build.sh sign         # builds build/grubx64.efi and a signed test copy
# optional: test build/grubx64.signed.efi in QEMU with OVMF Secure Boot + swtpm
./build.sh install      # copies to /boot/EFI/grub-fallback/ and signs it with sbctl -s
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
  --label "GRUB (fallback)" --loader '\EFI\grub-fallback\grubx64.efi'
```

Then put it after the two UKIs in `BootOrder` (section 15).

**Verify:** `sbctl verify` lists it as signed; `efibootmgr --bootnext <num>` and reboot:
the menu appears and both entries boot without a passphrase prompt.

Status on the reference machine: built, signed and installed; validated in QEMU/OVMF
with Secure Boot and a software TPM (chainload works, unsigned images and TPM-less
chainload are refused, PCR 7 identical to a direct UKI boot). Not yet exercised on the
G14's own firmware, so treat it as "probably works".

**Revert:** `efibootmgr -b <num> -B`, `rm -r /boot/EFI/grub-fallback`,
`sbctl remove-file /boot/EFI/grub-fallback/grubx64.efi`.

## 20. Switching to the custom kernel

The reference machine boots `linux-lapidary`, a CachyOS-based kernel with G14 display
patches. Building and installing it, and why, is in
[04-custom-packages.md](04-custom-packages.md). For the boot chain only three things
matter:

1. Install its preset as `/etc/mkinitcpio.d/linux-lapidary.preset`
   ([`system/etc/mkinitcpio.d/linux-lapidary.preset`](../system/etc/mkinitcpio.d/linux-lapidary.preset));
   installing the package builds `/boot/EFI/Linux/arch-linux-lapidary.efi`.
2. `sbctl sign -s /boot/EFI/Linux/arch-linux-lapidary.efi` once, so it stays signed.
3. Add the NVRAM entry and put it first (section 15).

The stock `linux` kernel stays installed with its own UKI and entry, as the fallback.
Keep both UKIs built from the same `/etc/kernel/cmdline` and `mkinitcpio.conf`: a
fallback that was built with an old config can fail in ways the main kernel does not.

## 21. Boot chain optimisations in effect

Current `systemd-analyze` on the reference machine:

```
Startup finished in 6.940s (firmware) + 408ms (loader) + 1.734s (kernel) + 1.997s (initrd) + 3.589s (userspace) = 14.670s
graphical.target reached after 3.449s in userspace.
```

The firmware's ~7 s is outside the OS's control. What makes the rest short:

| Change | Effect |
|---|---|
| UKI booted directly by firmware, no boot loader | loader stage ~0.4 s |
| `amdkms` hook instead of `kms` | UKI 207 MB -> 95 MB (no nouveau/GSP firmware); smaller image to read and verify |
| No `nvidia*` in `MODULES` | earlier: UKI 194 MB -> 94 MB for the same reason |
| amdgpu not in `MODULES` | initrd 3.74 s -> 2.44 s (unlock no longer waits for amdgpu) |
| crypttab with `x-initrd.attach` instead of `crypttab.initramfs` | current mkinitcpio method, no deprecation warning |
| Only the `default` preset, no per-kernel fallback image | less ESP space, faster `mkinitcpio -P` |
| `rootfstype=btrfs` | no filesystem probing |
| Masked `systemd-boot-update.service` | nothing to update without systemd-boot |
| Audio cap service waits for the sound card instead of a fixed `sleep` ([docs/03](03-g14-hardware-and-power.md)) | removed an 8 s block from userspace |

To check your own boot: `systemd-analyze`, `systemd-analyze blame`,
`systemd-analyze critical-chain`. A long "initrd" time that suddenly appears is usually
the TPM falling back to the passphrase prompt (the waiting time is counted as initrd).

## 22. Troubleshooting

- **Passphrase prompt instead of TPM unlock:** section 18, "known triggers".
- **Emergency mode after a kernel update:** boot the other UKI from the ESC menu, then
  `mkinitcpio -P`. Check that `/usr/lib/modules/$(uname -r)` exists for the kernel in
  the UKI that failed.
- **UKI suddenly ~200 MB:** the `kms` hook is back, or `nvidia` was added to `MODULES`.
- **mkinitcpio error about `g14-hdr.bin`:** the EDID file is missing; create it
  ([docs/03](03-g14-hardware-and-power.md)) or remove it from `FILES=` and the command line.
- **ESP full:** `du -sh /boot/*`; old `initramfs-*.img` files and UKIs of removed
  kernels are the usual culprits.
- **Boot from the live ISO later** (for repairs): Secure Boot has to be disabled for the
  Arch ISO. Doing so changes PCR 7, so the TPM slot will not unlock until Secure Boot is
  back on. Use the passphrase meanwhile:
  `cryptsetup open /dev/nvme0n1p2 root`, then mount as in section 6 and `arch-chroot`.
