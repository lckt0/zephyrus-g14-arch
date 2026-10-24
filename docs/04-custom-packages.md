# 04 - Custom packages

Packages on the reference machine that are built locally instead of coming from
the Arch, CachyOS or AUR repositories. For each one: what it changes compared
with upstream, why, why the change is not the upstream default, how to build and
install it, and how to go back to the stock package.

Only the packaging inputs are kept here (PKGBUILD, patches, install hooks, small
config files). Sources are downloaded by `makepkg`; no source trees or built
packages are included.

| Package | Directory | Status on the reference machine |
| --- | --- | --- |
| `linux-lapidary` (+ `-headers`) 7.2.7-1 | [`packages/linux-lapidary/`](../packages/linux-lapidary/) | installed, default boot entry |
| `plymouth-lapidary` 26.134.222-2 | [`packages/plymouth-lapidary/`](../packages/plymouth-lapidary/) | installed |
| `kwin` 6.8.1-2.2 with a layer repaint fix | [`packages/kwin-lapidary/`](../packages/kwin-lapidary/) | installed |

Other locally maintained software has its own repository and is not repeated here:

- [harfiyen](https://github.com/lckt0/harfiyen)
- [iris-desktop](https://github.com/lckt0/iris-desktop), [iris-greeter](https://github.com/lckt0/iris-greeter), [iris-volume](https://github.com/lckt0/iris-volume) (installed as `plasma-applet-lckt0-volume`)
- [onyx-greeter](https://github.com/lckt0/onyx-greeter), [gnomish-greeter](https://github.com/lckt0/gnomish-greeter)
- [zephyrusctl](https://github.com/lckt0/zephyrusctl) (no longer installed, see [03 section 16](03-g14-hardware-and-power.md#16-tried-and-dropped))
- [arch-update-gui](https://github.com/lckt0/arch-update-gui)

AUR packages in use are listed in [`packages/pkglist-foreign.txt`](../packages/pkglist-foreign.txt);
of those, `nvidia-laptop-power-cfg` matters for power and is described in
[03 section 4](03-g14-hardware-and-power.md#4-gpu-switching-supergfxctl-and-the-dgpu).

General build prerequisites:

```sh
sudo pacman -S --needed base-devel git
```

---

## linux-lapidary

**What.** The CachyOS kernel (`linux-cachyos`, 7.2.7-1, EEVDF "cachyos"
scheduler, Clang ThinLTO, `-O3`, native CPU optimisation) with three local
patches to the amdgpu display driver. The package is renamed so CachyOS updates
never overwrite it, and the stock Arch `linux` stays installed next to it as the
fallback.

**Upstream base.** `CachyOS/linux-cachyos`, file `linux-cachyos/PKGBUILD` at
commit `bd534465e6b8a6fe4483b0ee2c28cbaf00a9b285` ("7.2.7-1").

**Changes to the PKGBUILD** (the complete diff against that commit):

- `_pkgsuffix=lapidary` after the suffix logic, so `pkgbase=linux-lapidary` and
  `uname -r` ends in `-lapidary`.
- `source+=(...)` for the three patches below; the existing `prepare()` already
  applies every `*.patch` in `source`.
- matching `b2sums` entries.
- `_nv_ver` differs from upstream (an older value left over from the previous
  base); it is unused because `_build_nvidia_open=no` (the NVIDIA module comes
  from `nvidia-open-dkms`).

**Kernel config.** The `config` file is the unmodified CachyOS `config` from the
same commit (byte-identical); there is no local config delta. The final
`.config` differs from it only through the PKGBUILD's own build options (native
CPU, `-O3`, HZ 1000, full tickless, LTO). The running kernel's config is in
`/proc/config.gz`.

### Patches

All three touch `drivers/gpu/drm/amd/display/` only. Each file starts with a
commit-message style header that explains it in full.

**`0001-drm-amd-display-bound-dmub-wait-loops.patch` - bound every DMUB wait.**
On ASICs whose debug options set `.disable_timeout` (DCN 3.5, 3.6, 4.2), seven
DMUB/SMU wait loops become infinite: four `do { wait(MAX_WAIT_US) } while
(disable_timeout && status != OK)` loops, one if/else retry in
`dc_dmub_srv_is_hw_pwr_up()`, and two SMU loops where `max_retries++` cancels the
loop's own `max_retries--`. On this laptop a stuck DMUB then held the DC lock for
20+ minutes or, when reached from the vblank worker with interrupts off, tripped
the NMI hard lockup detector and took every CPU down with it (total freeze,
four times in two weeks). The patch bounds the retries to a 2 s budget so the
existing error paths are reachable again, and stops the SMU loops from cancelling
their counters.
*Why not upstream default:* AMD disabled the timeouts on purpose, on the
assumption that these waits only happen at low interrupt levels so a long wait
cannot trip a watchdog; the hard-lockup trace above contradicts that assumption.
As of 7.3-rc4 and the 7.4 staging tree (checked 2026-09-22) all seven loops are
still unbounded and there is no boot parameter to change it. The patch is
written to be submitted upstream but has not been sent yet. It applies to 7.3
with offsets; **it breaks on 7.4**, where `MAX_WAIT_US` became
`DMUB_CMD_DEFAULT_MAX_WAIT_US` and the calls take per-call timeouts, so it will
need rework there.

**`0002-drm-amd-display-min-sso-delay.patch` - minimum delay before PSR/Replay entry.**
The idle state machine enters "static screen optimisation" (PSR/Replay allowed)
after 11 frames, ~92 ms at 120 Hz. Every exit busy-waits until the panel is out
of self-refresh, and the next commit waits for that: the first flip after a short
pause took 4-5 vblanks (34-43 ms, ftrace), visible as cursor stutter. The patch
adds `amdgpu.dm_sso_min_ms` (default 250, runtime-writable, 0 = upstream
behaviour) as a lower bound for that delay. Other idle optimisations are
unchanged.
*Why not upstream default:* it is a tuning trade-off for this panel (self-refresh
starts later, so a little less time is spent in it) and was written as a local
patch, not for upstream.

**`0003-drm-amd-display-fix-edp-replay-vsdb.patch` - use the parsed AMD VSDB for eDP Replay detection.**
`amdgpu_dm_update_freesync_caps()` parses the AMD vendor-specific data block into
`vsdb_info` but then tests a separate, zero-initialised `vsdb_did` that is never
filled, so `replay_mode` is always 0 and Panel Replay never turns on. The patch
tests the structure that was actually filled, as mainline does. Worth about
0.75 W at idle on this machine.
*Why not upstream default:* it is a bug in the newer DC code that CachyOS
carries in its 7.2.6/7.2.7 trees, not in vanilla 7.2.y or mainline 7.3. It
should disappear when CachyOS rebases that code; drop the patch then.

**Not applied: `not-applied/0004-drm-amd-display-vrr-pull-in-all-planes.patch`.**
Upstream commit 3477c1b ("Add primary plane to commits for correct VRR
handling") pulls the primary plane into every non-cursor commit while VRR is
active, after all planes were already added; a cursor-only commit then reaches DC
holding only the primary plane and DC removes every overlay plane from the stream
(windows vanish while the mouse moves, with KWin's multi-plane layout). The patch
pulls in all non-cursor planes instead. It compiles but is **not in the running
kernel**, because VRR is kept at Never anyway ([03 section 7](03-g14-hardware-and-power.md#7-display-the-amdgpu-side)).
To use it, move it next to the others and add it to `source=()`.

### Build and install

Needs about 30 GB free disk space during the build (check with `df -h` first),
and roughly an hour on this CPU.

```sh
cd packages/linux-lapidary
# the CachyOS base config, byte-identical to the one used:
curl -LO https://raw.githubusercontent.com/CachyOS/linux-cachyos/bd534465e6b8a6fe4483b0ee2c28cbaf00a9b285/linux-cachyos/config
# signing keys of the CachyOS kernel tarball (see validpgpkeys in the PKGBUILD)
gpg --recv-keys E18447AC260021D31F3FF6C4C8A2A4774B8B63C4 E8B9AA39F054E30E8290D492C3C4820857F654FE
makepkg -s
sudo pacman -U linux-lapidary-7.2.7-1-x86_64.pkg.tar.zst linux-lapidary-headers-7.2.7-1-x86_64.pkg.tar.zst
```

`dkms-clang.patch` is downloaded from the CachyOS kernel-patches repository's
`master` branch; if its checksum no longer matches, fetch the version from the
date of the base commit or run `updpkgsums` after reviewing it.

Then the boot side, from [01 section 20](01-base-install.md#20-switching-to-the-custom-kernel):
install [`system/etc/mkinitcpio.d/linux-lapidary.preset`](../system/etc/mkinitcpio.d/linux-lapidary.preset)
**before** the package (so the install hook builds
`/boot/EFI/Linux/arch-linux-lapidary.efi`), sign it once with
`sudo sbctl sign -s /boot/EFI/Linux/arch-linux-lapidary.efi`, and add/put its
NVRAM entry first. NVIDIA DKMS modules are built for it by the headers package.

To move to a newer CachyOS version: take the new upstream PKGBUILD and config,
re-apply the PKGBUILD changes listed above, check every patch with
`patch -p1 --dry-run` in the extracted tree, then `updpkgsums`.

**Verify.**

```sh
uname -r                                              # 7.2.7-1-lapidary
cat /sys/module/amdgpu/parameters/dm_sso_min_ms       # 250 (patch 0002 present)
dmub-check                                            # 03 section 14
```

**Revert to stock.** Boot the stock `linux` entry (it is always kept), then:

```sh
sudo efibootmgr -o <stock-entry>,<lapidary-entry>     # stock first
sudo sbctl remove-file /boot/EFI/Linux/arch-linux-lapidary.efi
sudo pacman -R linux-lapidary linux-lapidary-headers
sudo rm /etc/mkinitcpio.d/linux-lapidary.preset
```

Without patch 0001 a DMUB hang is a hard freeze again; without 0003 Panel Replay
is off on the CachyOS kernel (the stock Arch kernel is vanilla-based and does not
have that bug).

---

## plymouth-lapidary

**What.** Arch's `plymouth` 26.134.222 with one patch that adds
`Plymouth.SetBootOutputFunction()` to the script plugin, plus the theme
`arch-loglu` ("Arch with logs") that uses it: the Arch logo on top and the real
kernel/systemd log scrolling underneath, on pure black, at boot and shutdown.

**Why.** Stock Plymouth cannot do this. The script plugin's sprite drawing
returns early while the console viewer is active, and the real log stream
(`/dev/kmsg` plus redirected console output) only goes to the plugin's
`on_boot_output()`, which is not exposed to the script language. The patch (about
60 lines in `plugin.c` and `script-lib-plymouth.[ch]`) passes that stream to the
theme line by line with ANSI escape sequences stripped.

*Why not upstream default:* it is a new script API. Nothing upstream needs it,
and it has not been proposed upstream.

**Base.** Arch's `plymouth` PKGBUILD for 26.134.222 (not CachyOS's
`plymouth-git`, whose snapshot is from 2024). Changes to the PKGBUILD:

- `pkgname=plymouth-lapidary`, `provides=(plymouth "plymouth=$pkgver")`,
  `conflicts=(plymouth plymouth-git)`. Under the stock name the next
  `pacman -Syu` would replace it silently with the repository build
  (`cachyos-extra-v4/plymouth` has a higher pkgrel).
- `_upstreamname=plymouth`, used for the git source and **for the installed
  mkinitcpio hook names**. Arch's `package()` installs the hooks as `$pkgname`;
  with the new name they would become `plymouth-lapidary`, the `plymouth` hook in
  `mkinitcpio.conf` would not be found and the machine would not boot.
- the patch is applied in `prepare()`.

`plymouth.initcpio_hook`, `plymouth.initcpio_install`,
`plymouth-shutdown.initcpio_install`, `50-plymouth.conf` and `plymouth.install`
are Arch's files, unchanged.

### Build and install

```sh
cd packages/plymouth-lapidary
makepkg -s
sudo pacman -U plymouth-lapidary-26.134.222-2-x86_64.pkg.tar.zst   # answer yes to replacing plymouth

# the theme (not part of the package)
sudo cp -r theme/arch-loglu /usr/share/plymouth/themes/
```

`/etc/plymouth/plymouthd.conf`:

```ini
[Daemon]
Theme=arch-loglu
ShowDelay=0
DeviceTimeout=8
```

**Check this after every install of the package:** pacman may move a hand-edited
`plymouthd.conf` to `.pacsave` and install the default, which silently switches
the theme back to `bgrt` - and the next UKI is built with the wrong theme. Then:

```sh
plymouth-set-default-theme              # must print arch-loglu
sudo mkinitcpio -P
```

The kernel command line needs `splash` and `loglevel=6`; with the default console
log level (4) the INFO lines that make the log readable are filtered out
([01 section 14](01-base-install.md#14-kernel-command-line-parameter-by-parameter)).
Plymouth runs with a device scale of 2 on this panel, so the theme sees a
1440x900 logical window; all sizes in the theme are relative.

**Verify.**

```sh
strings /usr/lib/plymouth/script.so | grep SetBootOutputFunction   # patch present
plymouth-set-default-theme                                         # arch-loglu
```

At the next boot the log lines should scroll under the logo.

On a stock Plymouth the theme still works, but the log panel stays empty
(Esc shows the built-in console).

**Updating.** When Arch releases a new Plymouth: bump `pkgver`, check the patch
with `git apply --check` in the new tag, `updpkgsums`, rebuild, and do the
`plymouthd.conf` check above.

**Revert to stock.**

```sh
sudo pacman -S plymouth                 # replaces plymouth-lapidary
# set Theme= to a stock theme (e.g. bgrt) in /etc/plymouth/plymouthd.conf, check for .pacsave
sudo mkinitcpio -P
```

---

## kwin-lapidary

**What.** Arch's `kwin` 6.8.1-2 package (the same sources CachyOS rebuilds as
6.8.1-2.1, including Arch's two NVIDIA fixes) with one extra patch,
`0001-compositor-repaint-reassigned-layers.patch`. The package keeps the stock
name `kwin` and stock dependencies, so it is a drop-in replacement.

**Status.** Installed as `kwin` 6.8.1-2.2. An earlier 6.8.0 build was replaced
by a regular repository update on 2026-10-22; the bug is still present in 6.8.1
(the code path is unchanged there and on master), so the patch was rebased and
the package rebuilt. A pacman hook (below) now warns when that happens again.

**Problem.** With overlay planes enabled (`KWIN_USE_OVERLAYS=1`, [03 section 8](03-g14-hardware-and-power.md#8-display-kwin-overlay-planes-and-direct-scanout)),
KWin moves the whole scene between output layers, for example when a notification
or tray popup that had its own plane closes. `Compositor::setupLayers()` only
calls `sceneView->setLayer(layer)`, which does not schedule a repaint, and
`renderLayers()` only renders layers that need one. The new layer is presented
with the buffer it still held (the closing popup) and the old scene layer is
switched off: windows and panels disappear for about 10 frames (~80 ms) and only
the wallpaper and the popup remain. Traced at the atomic commit level.

**Patch.** Schedule a full device repaint on a layer whenever the item assigned to
it changes (scene or overlay item). Cost: one full repaint on the frames where
layers are reassigned, i.e. when popups open or close.

*Why not upstream default:* overlay planes are off by default on AMD (and the bug
only shows when the scene itself moves between planes, i.e. in a multi-plane
layout), so few users hit it. It is a plain bug in KWin; it has not been reported
upstream yet.

### Version numbering

`pkgrel` is the repository build's pkgrel plus `.1`: CachyOS ships Arch's
`6.8.1-2` as `6.8.1-2.1`, so the local build is `6.8.1-2.2`. That sorts above the
build it replaces, but below the next repository release (`6.8.1-3`,
`6.8.1-3.1` or `6.8.2-1`), so normal updates are never blocked. The flip side is
that the next KWin update replaces the patched package; rebuild then.

### Build and install

The included PKGBUILD is the 6.8.1-2.2 one that is installed. It builds with
`BUILD_TESTING=OFF` like Arch's, so there is no `check()` step.

```sh
mkdir kwin-build && cd kwin-build
cp ../zephyrus-g14-arch/packages/kwin-lapidary/{PKGBUILD,0001-compositor-repaint-reassigned-layers.patch} .
makepkg -s                     # about 8 minutes on this machine
sudo pacman -U kwin-6.8.1-2.2-*.pkg.tar.zst
```

Log out and in; KWin cannot be replaced in a running session.

For a newer KWin, start from Arch's current packaging and add the patch:

```sh
pkgctl repo clone --protocol=https kwin && cd kwin     # or: git clone https://gitlab.archlinux.org/archlinux/packaging/packages/kwin.git
cp ../zephyrus-g14-arch/packages/kwin-lapidary/0001-compositor-repaint-reassigned-layers.patch .
# in PKGBUILD: add the patch to source=(), and to the end of prepare():
#   patch -d $pkgname-$pkgver -p1 < 0001-compositor-repaint-reassigned-layers.patch
# set pkgrel to the repository build's pkgrel + .1 (see above), and append
# " (lapidary: layer repaint fix)" to pkgdesc so the hook below recognises it
updpkgsums
makepkg -s
```

If the patch no longer applies, check `Compositor::setupLayers()` in
`src/compositor.cpp`; the two `setLayer()` call sites are what it changes.

### Update warning hook

[`system/etc/pacman.d/hooks/kwin-patch-check.hook`](../system/etc/pacman.d/hooks/kwin-patch-check.hook)
runs after every transaction that installs or upgrades `kwin`. If the installed
package's description does not contain "lapidary: layer repaint fix", it prints a
one-line warning in the pacman output and logs it to the journal
(`journalctl -t kwin-patch-check`). It changes nothing.

```sh
sudo install -Dm644 system/etc/pacman.d/hooks/kwin-patch-check.hook /etc/pacman.d/hooks/kwin-patch-check.hook
```

To keep the patched build through updates instead, hold it with
`IgnorePkg = kwin` in `/etc/pacman.conf`, and lift that before a Plasma upgrade
(KWin must match the rest of Plasma).

**Verify.** `pacman -Qi kwin | grep -E 'Version|Description'` shows `6.8.1-2.2`
and "(lapidary: layer repaint fix)". The running compositor uses it only if it
was started after the install time shown there (`ps -o lstart= -C kwin_wayland`).
Functional check: with overlays enabled, open and close
notifications repeatedly while moving the mouse; windows must not flash away.

**Revert to stock.** `sudo pacman -S kwin`, log out and in.

### Earlier KWin patches (dropped)

The 6.7.5-based `kwin-lapidary` had two other patches - amdgpu CRTC degamma
handling for direct scanout and a throttle for asynchronous cursor-plane test
commits (with a 1000 Hz mouse KWin did ~1000 full-state atomic tests per second).
They were dropped with the move to KWin 6.8, because the package pinned exact
Qt/Plasma versions and blocked updates. Not carried forward.
