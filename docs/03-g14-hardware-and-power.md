# 03 - G14 hardware and power

Everything that makes the ROG Zephyrus G14 behave well and run efficiently on
this install: battery, fans and LEDs, GPU switching, power profiles, the display
path (Panel Replay, VRR, overlay planes), audio, wireless, suspend, and the small
system files that hold it together. Every section describes the state the
reference machine is in **now**; things that were tried and removed are listed
at the end.

The custom kernel and Plymouth packages that some sections refer to are
documented in [04-custom-packages.md](04-custom-packages.md). Kernel command
line basics are in [01-base-install.md](01-base-install.md) (sections 13 and 14);
user-level settings (PowerDevil, mpv, KWin effects, helper scripts) are in
[05-dotfiles-and-desktop.md](05-dotfiles-and-desktop.md).

**[GA403GM]** marks things that are specific to the tested model. Other GA403
variants (GA403UI/UU/UV etc.) share the chassis and most of the platform and are
likely to behave similarly, but PCI addresses, codec subsystem IDs and the panel
can differ - check before copying.

## Contents

1. [Reference hardware](#1-reference-hardware)
2. [What is applied, at a glance](#2-what-is-applied-at-a-glance)
3. [asusd: battery limit, profiles, fans, LEDs](#3-asusd-battery-limit-profiles-fans-leds)
4. [GPU switching: supergfxctl and the dGPU](#4-gpu-switching-supergfxctl-and-the-dgpu)
5. [Power profiles: power-profiles-daemon](#5-power-profiles-power-profiles-daemon)
6. [CPU: scheduler, cpuidle, kernel knobs](#6-cpu-scheduler-cpuidle-kernel-knobs)
7. [Display: the amdgpu side](#7-display-the-amdgpu-side)
8. [Display: KWin overlay planes and direct scanout](#8-display-kwin-overlay-planes-and-direct-scanout)
9. [HDR: EDID override for the OLED panel](#9-hdr-edid-override-for-the-oled-panel)
10. [Audio: ALC285 + CS35L56](#10-audio-alc285--cs35l56)
11. [Wi-Fi and Bluetooth (AX210)](#11-wi-fi-and-bluetooth-ax210)
12. [Suspend, hibernate, shutdown](#12-suspend-hibernate-shutdown)
13. [Copilot key](#13-copilot-key)
14. [Watchers](#14-watchers)
15. [Measured numbers](#15-measured-numbers)
16. [Tried and dropped](#16-tried-and-dropped)

## 1. Reference hardware

| Part | Model | Notes |
| --- | --- | --- |
| Laptop | ASUS ROG Zephyrus G14 **GA403GM**, BIOS GA403GM.302 | 2025 model |
| CPU / iGPU | AMD Ryzen AI 9 465, Radeon 880M (Strix Point, `1002:150e`, DCN 3.5) | iGPU at `0000:65:00.0`, drives the internal panel and all USB-C DisplayPort outputs |
| dGPU | NVIDIA GeForce RTX 5060 Laptop (GB206M, `10de:2d59`) | at `0000:64:00.0`, HDA function `64:00.1`. **The HDMI port is wired to the dGPU.** |
| Panel | Samsung ATNA40HQ14, 14" OLED, 2880x1800, 30-120 Hz VRR, 10-bit | supports AMD Panel Replay and HDR (the latter only visible with an EDID fix, section 9) |
| Audio | Realtek ALC285 (subsystem `1043:1044`, `0000:65:00.6`) + 2x Cirrus CS35L56 amplifiers (I2C) | needs a quirk on kernels before 7.3 (section 10) |
| Wireless | Intel AX210NGW (Wi-Fi 6E + Bluetooth, USB `8087:0032`) | **not stock**: replaces the factory MediaTek MT7925 card (section 11) |
| SSD | KIOXIA BG6 NVMe | |
| Keyboard | ASUS N-Key (USB `0b05:19b6`) with single-zone white backlight, Slash LED bar on the lid | |

Useful commands to compare with your machine:

```sh
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/bios_version
lspci -nn | grep -Ei 'vga|3d|display|audio|network'
for c in /sys/class/sound/hwC*D0; do echo "$c $(cat $c/vendor_id $c/subsystem_id)"; done
```

## 2. What is applied, at a glance

| Area | Mechanism | Files in this repo |
| --- | --- | --- |
| Charge limit 80 % | asusd | [`system/etc/asusd/asusd.ron`](../system/etc/asusd/asusd.ron) |
| Fan curves, keyboard light, Slash | asusd | `system/etc/asusd/{fan_curves,aura_19b6,slash}.ron` |
| dGPU off unless asked for | supergfxctl, mode `Integrated` | [`system/etc/supergfxd.conf`](../system/etc/supergfxd.conf) |
| NVIDIA runtime PM | modprobe options + udev rule | [`system/etc/modprobe.d/nvidia.conf`](../system/etc/modprobe.d/nvidia.conf), [`nouveau-blacklist.conf`](../system/etc/modprobe.d/nouveau-blacklist.conf), [`system/etc/udev/rules.d/80-nvidia-pm.rules`](../system/etc/udev/rules.d/80-nvidia-pm.rules) |
| Power profiles | power-profiles-daemon (stock service) | - |
| Fewer idle wakeups | lazy RCU (cmdline), NMI watchdog off, slower dirty writeback | [`system/etc/sysctl.d/`](../system/etc/sysctl.d/) |
| Panel Replay, DMUB freeze fix, PSR entry delay | patched kernel `linux-lapidary` | [`packages/linux-lapidary/`](../packages/linux-lapidary/) |
| Overlay planes / direct scanout | KWin environment variables, visual effects off | [`home/.config/plasma-workspace/env/kwin-overlay.sh`](../home/.config/plasma-workspace/env/kwin-overlay.sh) |
| HDR on the OLED | EDID override | [`system/usr/local/bin/hdr-edid-patch.py`](../system/usr/local/bin/hdr-edid-patch.py) |
| Speakers / woofers | HDA patch firmware, hardware mixer pinned, port watcher | [`system/usr/lib/firmware/alc285-g14-ga403gm.fw`](../system/usr/lib/firmware/alc285-g14-ga403gm.fw), [`system/etc/modprobe.d/60-alc285-g14-quirk.conf`](../system/etc/modprobe.d/60-alc285-g14-quirk.conf), [`system/usr/local/bin/`](../system/usr/local/bin/) |
| Bluetooth stability | btusb autosuspend off | [`system/etc/modprobe.d/btusb-no-autosuspend.conf`](../system/etc/modprobe.d/btusb-no-autosuspend.conf) |
| Sleep | s2idle only, hibernate masked | - |
| Watchers | DMUB events, stuck tasks / awake dGPU | [`home/.local/bin/`](../home/.local/bin/), [`home/.config/systemd/user/`](../home/.config/systemd/user/) |

All commands below are run from a clone of this repository:

```sh
git clone https://github.com/lckt0/zephyrus-g14-arch.git
cd zephyrus-g14-arch
```

## 3. asusd: battery limit, profiles, fans, LEDs

**What.** `asusctl` 6.5 (the `asusd` daemon) from the CachyOS repository. asusd
is D-Bus activated, so it does not need to be enabled. It owns:

- the battery charge limit,
- switching the ACPI platform profile when the charger is plugged or unplugged,
- the fan curves for each platform profile,
- the keyboard backlight (aura) and the Slash LED bar,
- some firmware attributes (boot sound).

```sh
sudo pacman -S asusctl
```

asusd writes its state back to `/etc/asusd/*.ron` on every change and on exit,
so **configure it with `asusctl` while it runs** rather than copying files over a
running daemon. The `.ron` files in [`system/etc/asusd/`](../system/etc/asusd/)
show the resulting state on the reference machine.

### Battery charge limit 80 %

**Why.** The laptop is plugged in most of the time; holding a Li-ion cell at
100 % ages it faster. TLP is not used (section 16), so asusd is the only thing
that sets the threshold.

```sh
asusctl battery limit 80
```

This writes `charge_control_end_threshold: 80` and
`base_charge_control_end_threshold: 80` to `/etc/asusd/asusd.ron`; asusd
re-applies it at every boot.

**Verify.**

```sh
cat /sys/class/power_supply/BAT1/charge_control_end_threshold   # 80
asusctl battery info
```

One full charge (for a trip): `asusctl battery oneshot`. **Revert:**
`asusctl battery limit 100`.

### Platform profile on AC / battery

`asusd.ron` on this machine:

```ron
platform_profile_linked_epp: true,
platform_profile_on_battery: Quiet,
change_platform_profile_on_battery: true,
platform_profile_on_ac: Performance,
change_platform_profile_on_ac: true,
profile_quiet_epp: Power,
profile_balanced_epp: BalancePower,
profile_performance_epp: Performance,
disable_nvidia_powerd_on_battery: false,
```

So asusd switches to `quiet` (EPP `power`) when the charger is pulled and to
`performance` when it is plugged in. power-profiles-daemon (section 5) reads and
writes the same `platform_profile`, so KDE's power applet shows what asusd set and
can still override it until the next plug event.

**`disable_nvidia_powerd_on_battery: false` is deliberate.** With `true`, asusd
stops `nvidia-powerd` on battery and *starts* it again on AC. After a resume on
AC, the restarted `nvidia-powerd` ran `modprobe nvidia`, which bypassed the
blacklist that supergfxd writes for Integrated mode; the module load hung in the
NVIDIA resource manager (D state, only a reboot clears it), the dGPU stayed in D0
and idle power went up by about 8 W. With `false` asusd leaves the service alone.

### Fan curves

`fan_curves.ron` holds 8-point curves (temperature in degrees C, PWM 0-255) for
the CPU, GPU and middle fan in each of `quiet`, `balanced` and `performance`, all
enabled. Read or change them with:

```sh
asusctl fan-curve --mod-profile quiet                     # show
asusctl fan-curve --mod-profile quiet --fan cpu --data 43c:1%,68c:6%,70c:8%,72c:13%,74c:18%,76c:22%,78c:32%,100c:32%
asusctl fan-curve --mod-profile quiet --enable-fan-curves true
asusctl fan-curve --default                               # active profile back to firmware default
```

Under sustained load in `performance` the package power limit is about 38 W and
Tctl sits around 85 C, which is normal for Strix Point. Faster fans only buy
3-5 C; the real lever is the profile (power limit), not the curve.

### Keyboard light, Slash, boot sound

- `aura_19b6.ron`: static white, brightness low, on in every power state.
  `asusctl aura` / `asusctl leds set low`.
- `slash.ron`: the lid LED bar is **off** (`enabled: false`). A toggle bound to a
  Fn key is described in [05 section 12](05-dotfiles-and-desktop.md#12-g14-hardware-helpers).
- `armoury_settings: { BootSound: 0 }`: POST chime off
  (`asusctl armoury` or `/sys/class/firmware-attributes/asus-armoury/attributes/boot_sound`).

## 4. GPU switching: supergfxctl and the dGPU

**What.** `supergfxctl` 5.2.7 (CachyOS repository), `supergfxd.service`
enabled, mode **Integrated**:

```json
{
  "mode": "Integrated",
  "vfio_enable": false,
  "vfio_save": false,
  "always_reboot": false,
  "no_logind": false,
  "logout_timeout_s": 180,
  "hotplug_type": "None"
}
```

```sh
sudo pacman -S supergfxctl
sudo systemctl enable --now supergfxd
sudo install -Dm644 system/etc/supergfxd.conf /etc/supergfxd.conf   # or: supergfxctl -m Integrated
```

In Integrated mode supergfxd writes `/etc/modprobe.d/supergfxd.conf`
(blacklists `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`, `nouveau`) -
that file is generated, do not copy or edit it. The dGPU stays on the PCI bus but
no driver binds and the PCI core keeps it in **D3cold**.

**Why.** Nothing in daily use needs the RTX 5060, and an awake dGPU costs several
watts. A dGPU that is merely "idle" with the NVIDIA driver loaded can still be
woken by anything that opens it (KWin enumerating DRM devices, `nvidia-smi`,
monitoring tools) - in Integrated mode nothing can.

**Trade-offs.**

- **HDMI does not work in Integrated mode**, because the HDMI connector is on
  the dGPU. The USB-C ports (DisplayPort alt mode) are on the iGPU, so a
  USB-C-to-HDMI/DP adapter works without waking the dGPU.
- Switching to Hybrid (`supergfxctl -m Hybrid`) logs you out (supergfxd waits for
  logout and stops the display manager). Do it from a state where losing the
  session is fine.
- `always_reboot` and `no_logind` must stay `false`. With either one set,
  supergfxd skips the "stop display manager" step but still kills every process
  holding `/dev/nvidia*` - including `kwin_wayland`, which looks like a freeze.
- Returning from Integrated to Hybrid with `"hotplug_type": "None"` has not been
  tested on this machine; if the card does not come back, try `"Asus"`, which
  uses the firmware `dgpu_disable` switch instead.
- After every resume, PCIe hotplug re-announces the card ("Card present" in
  the journal). Harmless: no driver binds and it drops back to D3cold.
- `nvidia-powerd.service` (Dynamic Boost) is disabled on this machine. It
  failed on every boot: in Integrated mode because the module is not loaded
  (`start-limit-hit`), and with the module loaded it exits with
  `ERROR! Allocate Root client failed 0x59`; Dynamic Boost does not work with
  this dGPU/firmware combination. `sudo systemctl disable nvidia-powerd`; see also the
  `disable_nvidia_powerd_on_battery` note in section 3.

**NVIDIA runtime PM for Hybrid mode.** When the dGPU is in use, these keep it
able to sleep:

- [`system/etc/modprobe.d/nvidia.conf`](../system/etc/modprobe.d/nvidia.conf)
  (owned by the AUR package `nvidia-laptop-power-cfg`, one local addition):
  `NVreg_DynamicPowerManagement=0x02` (fine-grained runtime D3),
  `NVreg_EnableS0ixPowerManagement=1`, and `NVreg_PreserveVideoMemoryAllocations=1`
  because `nvidia-suspend/resume/hibernate.service` are enabled - without it
  resume logged `RmHandleDNotifierEvent failed` and the card kept bouncing
  between D0 and D3cold.
- [`system/etc/udev/rules.d/80-nvidia-pm.rules`](../system/etc/udev/rules.d/80-nvidia-pm.rules)
  overrides the package's rule of the same name: it sets `power/control=auto`
  for the VGA/3D function **and the HDA audio function** (`0x040300`) when they
  appear, and leaves out the package's "remove NVIDIA xHCI/UCSI" rules.
- [`system/etc/modprobe.d/nouveau-blacklist.conf`](../system/etc/modprobe.d/nouveau-blacklist.conf):
  nouveau never loads, independent of the supergfxd mode.
- `systemd-backlight@backlight:nvidia_0.service` is masked: it restored a stale
  `nvidia_0` backlight that the panel does not use and was the first thing to
  touch the dGPU at boot.

```sh
sudo install -Dm644 system/etc/modprobe.d/nvidia.conf /etc/modprobe.d/nvidia.conf
sudo install -Dm644 system/etc/modprobe.d/nouveau-blacklist.conf /etc/modprobe.d/
sudo install -Dm644 system/etc/udev/rules.d/80-nvidia-pm.rules /etc/udev/rules.d/
sudo systemctl mask systemd-backlight@backlight:nvidia_0.service
```

**Verify.**

```sh
supergfxctl -g                                          # Integrated
supergfxctl -S                                          # suspended / off
cat /sys/bus/pci/devices/0000:64:00.0/power_state       # D3cold   [GA403GM address]
lsmod | grep -E '^nvidia|^nouveau'                      # only nvidia_wmi_ec_backlight
```

**Revert.** `supergfxctl -m Hybrid` (logs out); delete the files above;
`sudo systemctl unmask systemd-backlight@backlight:nvidia_0.service`.

## 5. Power profiles: power-profiles-daemon

**What.** `power-profiles-daemon` 0.30 with its stock service, using the
`amd_pstate` (amd-pstate-epp) CPU driver and the ACPI `platform_profile`
driver. No TLP, no tuned. KDE's battery applet and PowerDevil talk to it
(PowerDevil profile choices: [05 section 11](05-dotfiles-and-desktop.md#11-power-related-user-settings)).

```sh
sudo pacman -S power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
```

What each profile does on this machine (measured, not assumed):

| PPD profile | platform_profile | governor | EPP | boost | iGPU DPM |
| --- | --- | --- | --- | --- | --- |
| power-saver | quiet | powersave | power | on | auto |
| balanced | balanced | powersave | balance_performance | on | auto |
| performance | performance | performance | performance | on | auto |

Two expectations that turned out wrong: power-saver does **not** pin the iGPU to
its lowest DPM level (that action is opt-in in PPD and off by default), and boost
stays on in all three. No drop-in is needed to prevent either.

**Repository note.** With the CachyOS repositories listed before `[extra]`,
`pacman -S power-profiles-daemon` installs the CachyOS build, which adds a
bridge to `scx_loader` (it switches sched-ext schedulers on profile changes).
The reference machine currently runs that build, but `scx_loader` is disabled
(section 6), so the bridge does nothing. If you want the plain Arch build:
`sudo pacman -S extra/power-profiles-daemon`.

**Verify.** `powerprofilesctl` (shows `CpuDriver: amd_pstate`,
`PlatformDriver: platform_profile`), `cat /sys/firmware/acpi/platform_profile`,
`cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference`.

## 6. CPU: scheduler, cpuidle, kernel knobs

- **Scheduler: the kernel's own (EEVDF).** `scx-scheds` is installed but
  `scx_loader.service` is disabled and `/sys/kernel/sched_ext/state` reads
  `disabled`. Reason in section 16.
- **cpuidle governor: `menu`** (the default). `teo` was measured and was worse.
- **Lazy RCU.** `rcu_nocbs=all rcutree.enable_rcu_lazy=1` on the kernel command
  line (explained in [01 section 14](01-base-install.md#14-kernel-command-line-parameter-by-parameter)).
  Batches non-urgent RCU callbacks; local timer interrupts at idle roughly halved,
  about 0.1 W lower idle power.
- **NMI watchdog off**,
  [`system/etc/sysctl.d/91-nmi-watchdog.conf`](../system/etc/sysctl.d/91-nmi-watchdog.conf):
  about 0.1 W at idle (at the edge of measurement noise). Turn it back on
  (`sysctl kernel.nmi_watchdog=1`) when chasing hard lockups.
- **Dirty writeback every 15 s instead of 5 s**,
  [`system/etc/sysctl.d/90-dirty-writeback.conf`](../system/etc/sysctl.d/90-dirty-writeback.conf):
  the NVMe drive is woken less often at idle. Data written by applications that
  do not `fsync` can sit in RAM up to 15 s longer.
- `zswap.enabled=0`: zram is used for swap instead ([01 section 12](01-base-install.md#12-swap-zram--swapfile)).

```sh
sudo install -Dm644 -t /etc/sysctl.d system/etc/sysctl.d/*.conf
sudo sysctl --system
```

**Verify.** `sysctl kernel.nmi_watchdog vm.dirty_writeback_centisecs`,
`cat /sys/devices/system/cpu/cpuidle/current_governor`,
`cat /sys/kernel/sched_ext/state`. **Revert.** Delete the files, reboot.

## 7. Display: the amdgpu side

The internal OLED is the biggest single consumer after the SoC, and most of the
work in this setup went into letting the panel and display engine idle. Four
local kernel patches live in [`packages/linux-lapidary/`](../packages/linux-lapidary/);
[04-custom-packages.md](04-custom-packages.md#linux-lapidary) has the details,
the upstream status and how to build it. Summary of what runs now:

### DMUB freeze protection (patch 0001)

On DCN 3.5 the display microcontroller (DMUB) occasionally stops answering. The
driver sets `.disable_timeout = true` for this generation, which turns seven
"wait with timeout" loops into infinite loops. One of them is reached with
interrupts disabled, and the result was a total freeze (Caps Lock LED dead,
NMI hard lockup, then every CPU stuck in TLB shootdown). This happened four
times in two weeks. The patch bounds every one of those waits to ~2 s so the
existing error paths run instead. It does not fix why DMUB stops; it turns a
freeze into a logged error. No boot parameter can do this - there is no
`dcdebugmask` bit for `disable_timeout`.

`dmub-watch` (section 14) reports when the bounded wait actually triggers.

### Panel Replay (patch 0003)

The ATNA40HQ14 supports AMD Panel Replay: the panel refreshes itself from its own
memory while the screen is static, and the link and much of the display engine
can sleep. The CachyOS kernel trees for 7.2.6 and 7.2.7 contain a refactored DC
copy where the Replay capability parsed from the EDID is stored in one variable
and tested in another (`vsdb_did`, always zero), so Replay is never enabled
(debugfs then says "Sink support: no", which is the driver's verdict, not a
hardware reading). Vanilla 7.2.y and mainline 7.3 do not have this bug. Patch
0003 tests the right variable; Replay is on by default on DCN 3.5.

Measured: idle power 4.62 W -> 3.87 W (about 0.75 W) with Replay working.

Check (root; each read sends a DMUB command, so read it once, do not poll it):

```sh
sudo cat /sys/kernel/debug/dri/1/eDP-1/replay_capability   # card index may differ
sudo cat /sys/kernel/debug/dri/1/eDP-1/replay_state
```

To turn Replay off without rebuilding: add `amdgpu.dcdebugmask=0x400`
(`DC_DISABLE_REPLAY`) to the kernel command line.

**Open issue.** Popups (notifications, tray menus) opening or closing sometimes
make windows disappear for a moment. The buffers KWin presents are correct when
captured, and the effect could not be reproduced with CRC capture enabled -
which disables Replay. Replay is therefore the main suspect, but this is not
confirmed. The KWin-side bug of the same shape is fixed by the KWin patch in
[04](04-custom-packages.md#kwin-lapidary).

### PSR entry delay (patch 0002)

When the screen goes idle, the driver enters self-refresh after 11 frames
(~92 ms at 120 Hz). Leaving self-refresh blocks the next commit for 4-5 frames,
which showed up as cursor stutter after short pauses. The patch adds a lower bound,
the module parameter `amdgpu.dm_sso_min_ms` (default 250 ms, writable at runtime,
0 restores upstream behaviour):

```sh
cat /sys/module/amdgpu/parameters/dm_sso_min_ms        # 250
echo 0 | sudo tee /sys/module/amdgpu/parameters/dm_sso_min_ms   # upstream behaviour, until reboot
```

### PSR

Not used, and there is no supported way to enable it here: AMD disabled PSR-SU
in the driver ("Temporarily disable PSR-SU to avoid glitches", an unconditional
`return false`), and `amdgpu.dcfeaturemask` is not even read for PSR on DCN 3.5.
Panel Replay is the self-refresh mechanism on this panel.

### Refresh rate and VRR

Current setting: 2880x1800 @ **120 Hz**, VRR **Never**, 150 % scale, HDR off,
colour power preference "prefer efficiency" (System Settings > Display).

- 60 Hz saves about 0.45 W at idle. The panel offers a native
  `2880x1800@60` mode, no custom mode needed. For long video sessions there is a
  manual switch, `video-mode` ([05 section 11](05-dotfiles-and-desktop.md#11-power-related-user-settings)).
- **VRR "Always" is not used.** It saved power without Replay, but (a) with Replay
  working it costs about 0.4 W at idle, because the driver disables Replay (and
  PSR) whenever VRR is active, and keeps the vblank interrupt running; and (b) it
  triggers a driver bug: on every cursor-only commit the driver pulls the primary
  plane into the commit and DC then drops all overlay planes, so windows vanish
  while the mouse moves. A fix is written
  ([`packages/linux-lapidary/not-applied/0004-*.patch`](../packages/linux-lapidary/not-applied/))
  but not built into the running kernel. Keep VRR at Never or Automatic.

### CACP (future)

Content Adaptive backlight Power (AMD's OLED power saving) landed in 7.3. This
panel meets its conditions (DCN >= 3.1.4, eDP, OLED). On 7.3+ it should appear
as `/sys/class/drm/card*-eDP-1/amdgpu/panel_power_savings`. Not available on
the 7.2.7 kernel used now.

## 8. Display: KWin overlay planes and direct scanout

**What.** KWin can put windows, video and the cursor on hardware planes (the
Linux counterpart of Windows' MPO) and scan a fullscreen client out directly,
skipping composition. On amdgpu this is opt-in. The environment file
[`home/.config/plasma-workspace/env/kwin-overlay.sh`](../home/.config/plasma-workspace/env/kwin-overlay.sh)
is sourced before KWin starts:

```sh
export KWIN_USE_OVERLAYS=1                # overlay planes on amdgpu
export KWIN_DRM_PREFER_COLOR_DEPTH=30     # 32 bpp AR30/AB30 scanout, never 64 bpp FP16
export KWIN_DRM_USE_COLOR_PIPELINE=0      # no per-plane colour pipelines
```

**Why each line.**

- `KWIN_USE_OVERLAYS=1`: KWin enables overlays by default only on Intel. The
  old reason for excluding AMD (overlay planes missing `COLOR_ENCODING` /
  `COLOR_RANGE`) does not hold on current kernels: `modetest -M amdgpu -p` shows
  three overlay planes per CRTC with NV12/P010 and both properties.
- `KWIN_DRM_PREFER_COLOR_DEPTH=30`: without it KWin may use FP16 (AB48) buffers,
  which doubles scanout traffic (~5 GB/s instead of ~2.5 GB/s at 120 Hz). The
  value is 30, not 24: with 24 KWin sometimes picks RGBA8888, which amdgpu
  advertises with DCC but rejects at framebuffer creation, and that frame loses
  the window layer.
- `KWIN_DRM_USE_COLOR_PIPELINE=0`: a colour pipeline on a plane makes KWin
  refuse YUV content on it, so video can never reach a plane; and KWin 6.8.0
  enabled it by default with visibly wrong colours on AMD's low-resolution LUTs
  (KDE bug 525839). 6.8.1 changed the default back; the line is now redundant but
  harmless. **Never set it to 1.**

Also required:

- **All visual KWin effects off.** Any active effect that blocks direct scanout
  (dim inactive did, permanently) forces full composition. The list and the
  behaviour scripts that stay on are in
  [05 section 8](05-dotfiles-and-desktop.md#8-kwin-effects-off-behaviour-scripts-on).
- **mpv** with `hwdec=vaapi`, `vo=dmabuf-wayland` and an SDR gamma-2.2 profile
  so decoded video can go to a plane untouched (`home/.config/mpv/mpv.conf`,
  [05 section 11](05-dotfiles-and-desktop.md#11-power-related-user-settings)).
- Display settings: HDR off, colour power preference "prefer efficiency".

```sh
install -Dm644 home/.config/plasma-workspace/env/kwin-overlay.sh ~/.config/plasma-workspace/env/kwin-overlay.sh
# log out and in
```

**Verify.**

```sh
tr '\0' '\n' < /proc/$(pgrep -x kwin_wayland)/environ | grep KWIN_
sudo cat /sys/kernel/debug/dri/1/state | grep -E '^plane|fb=|crtc=' | head -40   # overlay planes with fbs
```

**Limits worth knowing.** Video decoding itself keeps the GPU at roughly 15-28 %
on this machine whatever the plane setup; planes save composition work, not
decode work (playing video costs about +2 W either way). Chromium-based browsers
do not hand video to the compositor as a separate surface on Linux, so browser
video is composited; mpv benefits most.

**Revert.** Delete the env file and log in again.

## 9. HDR: EDID override for the OLED panel

**[GA403GM]** **What.** KDE does not offer HDR for the internal panel out of the
box. The panel's EDID puts its Colorimetry (BT.2020) and HDR Static Metadata
(ST 2084) blocks inside a DisplayID 2.0 extension, where libdisplay-info 0.3 (and
so KWin) does not look. The script
[`system/usr/local/bin/hdr-edid-patch.py`](../system/usr/local/bin/hdr-edid-patch.py)
copies those two blocks into an extra top-level CTA-861 extension, bumps the
extension count and fixes checksums (384 -> 512 bytes). The kernel then loads
the patched EDID via `drm.edid_firmware=`.

HDR is currently **off** on the reference machine (it costs about 0.2 W), but the
override stays so it can be switched on in System Settings at any time.

**How.** Dump the EDID **before** any override is active (the sysfs file shows
the override once it is loaded):

```sh
cp /sys/class/drm/card*-eDP-1/edid ~/edid-orig.bin
python3 system/usr/local/bin/hdr-edid-patch.py ~/edid-orig.bin ~/edid-hdr.bin
sudo install -Dm644 ~/edid-hdr.bin /usr/lib/firmware/edid/g14-hdr.bin
```

Then, as described in [01 sections 13-14](01-base-install.md#13-initramfs-and-uki):
`FILES=(/usr/lib/firmware/edid/g14-hdr.bin)` in `/etc/mkinitcpio.conf` (it must be
in the UKI), `drm.edid_firmware=eDP-1:edid/g14-hdr.bin` in `/etc/kernel/cmdline`,
`sudo mkinitcpio -P`, reboot. The EDID contains your panel's serial data, so
generate your own; do not copy someone else's binary.

**Verify.**

```sh
stat -c %s /sys/class/drm/card*-eDP-1/edid           # 512
md5sum /sys/class/drm/card*-eDP-1/edid /usr/lib/firmware/edid/g14-hdr.bin   # equal
edid-decode /sys/class/drm/card*-eDP-1/edid | grep -c 'HDR Static Metadata'  # 2
```

amdgpu still logs "Using ACPI provided EDID for eDP-1"; the DRM override wins
anyway (the md5 check above is the proof). KWin keys its per-output settings on
an EDID hash, so display settings reset once when the override first appears.

**Revert.** Remove the cmdline parameter and the `FILES=` entry, `mkinitcpio -P`,
reboot.

## 10. Audio: ALC285 + CS35L56

Three independent pieces.

### 10.1 Codec quirk via HDA patch firmware [GA403GM]

**Problem.** On kernels before 7.3 the GA403GM's codec subsystem ID `1043:1044`
is not in the Realtek quirk table. Without the GA403U fixup, pin 0x17 (the
woofer path) sits on DAC 0x06, which has no volume control, so the volume slider
only affects the tweeters and the headset mic pins are not set up. Upstream fixed
this in 7.3 (commit 140fe610af60).

**Fix without rebuilding the kernel.** An HDA "patch" firmware file tells
`snd_hda_intel` to treat the codec as model `1043:1b13` (GA403U), which selects
the same fixup chain upstream uses:

- [`system/usr/lib/firmware/alc285-g14-ga403gm.fw`](../system/usr/lib/firmware/alc285-g14-ga403gm.fw)
- [`system/etc/modprobe.d/60-alc285-g14-quirk.conf`](../system/etc/modprobe.d/60-alc285-g14-quirk.conf):
  `options snd_hda_intel patch=alc285-g14-ga403gm.fw,...` given three times,
  because the array index is the controller probe order, which shifts when the
  dGPU's HDMI audio disappears. The file's `[codec]` line only matches the ALC285,
  so it is a no-op on the HDMI controllers.

```sh
sudo install -Dm644 system/usr/lib/firmware/alc285-g14-ga403gm.fw /usr/lib/firmware/alc285-g14-ga403gm.fw
sudo install -Dm644 system/etc/modprobe.d/60-alc285-g14-quirk.conf /etc/modprobe.d/
# reboot (snd modules are not in the UKI, no mkinitcpio needed)
```

**Verify.**

```sh
journalctl -k -b | grep -E 'Applying patch firmware|picked fixup'
#   ... 0000:65:00.6: Applying patch firmware 'alc285-g14-ga403gm.fw'
#   ... ALC285: picked fixup  for alias SSID 1043:1b13
cat /sys/class/sound/hwC*D0/modelname        # 1043:1b13 for the ALC285 codec
grep -A3 'Node 0x17' /proc/asound/card*/codec#0 | grep Connection   # 0x02
```

**Revert / on 7.3+.** Delete both files and reboot.

The CS35L56 amplifiers bind regardless of the quirk. There is no
`CirrusSmartAmpCalibrationData` EFI variable on this machine, so the factory
speaker calibration is not applied (the kernel reports `patched=0`); nothing to
fix from Linux.

### 10.2 Hardware mixer pinned, software volume

- [`home/.config/wireplumber/wireplumber.conf.d/99-alsasoftvol.conf`](../home/.config/wireplumber/wireplumber.conf.d/99-alsasoftvol.conf)
  sets `api.alsa.soft-mixer = true` for all ALSA cards: PipeWire does volume in
  software and never touches the hardware mixer.
- [`system/usr/local/bin/alc285-volume-cap`](../system/usr/local/bin/alc285-volume-cap)
  + [`alsa-card-volume-cap.service`](../system/etc/systemd/system/alsa-card-volume-cap.service)
  set `Master`, `AMP1 Speaker` and `AMP2 Speaker` to 100 % at boot so the
  software volume has the full range to work with. The service is `Type=simple`
  on purpose: the card appears a couple of seconds into userspace and a oneshot
  waiting for it held `multi-user.target` back.
- [`system/usr/local/bin/alc285-card`](../system/usr/local/bin/alc285-card)
  prints the ALSA card index of the ALC285, resolved from its PCI address
  (`0000:65:00.6`, override with `ALC285_PCI=`). The index is **not** stable: when
  the dGPU's HDMI audio function disappears, every later card moves down by one.
  A hard-coded `-c 2` once broke all of this silently.

Note that with the hardware mixer at 100 %, `AMP1/AMP2 Speaker` end up at the
top of their range (+12 dB over the driver default of 0 dB). That is how the
machine runs; lower them with `amixer` if your speakers distort.

### 10.3 Speakers after unplugging headphones

The speakers, especially the bass speakers, do not reliably unmute after
headphones are removed (soft-mixer plus "Auto-Mute Mode" disabled means nothing
else does it). A user service watches the sink's active port and fixes the mixer:
`home/.local/bin/alc285-port-watch`, `home/.local/bin/alc285-audio-fix`,
[`home/.config/systemd/user/alc285-port-watch.service`](../home/.config/systemd/user/alc285-port-watch.service).
Both scripts call `/usr/local/bin/alc285-card`. Described in
[05 section 12](05-dotfiles-and-desktop.md#12-g14-hardware-helpers).

```sh
sudo install -Dm755 -t /usr/local/bin system/usr/local/bin/alc285-card system/usr/local/bin/alc285-volume-cap
sudo install -Dm644 system/etc/systemd/system/alsa-card-volume-cap.service /etc/systemd/system/
sudo systemctl enable alsa-card-volume-cap.service
install -Dm644 home/.config/wireplumber/wireplumber.conf.d/99-alsasoftvol.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber
```

**Verify.** `alc285-card` prints a number;
`amixer -c "$(alc285-card)" get Master`; `systemctl status alsa-card-volume-cap`.
**Revert.** Disable the service, delete the files, restart WirePlumber.

**Dropped: a local WirePlumber `alsa.lua` override.** For a while
`~/.local/share/wireplumber/scripts/monitors/alsa.lua` held a patched copy of
WirePlumber's ALSA monitor against "ghost" duplicate sinks piling up on every
card profile change (old nodes were released but not destroyed and kept the
PCM busy). Half of that fix went upstream in 0.5.17; the other half
(`request_destroy` in `removeNode`) did not. The copy was based on 0.5.17 and,
once 0.5.18 was installed, shadowed that release's fixes, so it was removed
and the packaged monitor is used. If duplicate sinks show up again after
profile switches, compare with the current upstream file before reviving the
idea.

## 11. Wi-Fi and Bluetooth (AX210)

The GA403GM ships with a MediaTek MT7925 card (Wi-Fi 7, 2x2, Bluetooth 5.4). It did
not work well with the Linux drivers, so it was replaced with an Intel AX210NGW
(Wi-Fi 6E + Bluetooth 5.3, M.2 2230), which `iwlwifi`/`btusb` support out of the box.
Everything below is about the AX210; on a stock unit with the MT7925 it does not apply.

- **Bluetooth autosuspend off**:
  [`system/etc/modprobe.d/btusb-no-autosuspend.conf`](../system/etc/modprobe.d/btusb-no-autosuspend.conf)
  (`options btusb enable_autosuspend=0`). With autosuspend the adapter slept after
  a few idle seconds and A2DP dropped with HCI transport errors. After the change
  the adapter's `runtime_suspended_time` stops growing and long A2DP streams run
  clean.
- **Wi-Fi power save: kernel/NetworkManager default (on).** It used to be forced
  off through TLP because Wi-Fi sleep cycles on the shared radio delayed Bluetooth
  packets. Since TLP was removed it is back to the default; if Bluetooth audio
  stutters while Wi-Fi is busy, try
  `nmcli connection modify <name> 802-11-wireless.powersave 2` (disable) and
  compare.
- Set the regulatory domain (`wireless-regdb` package,
  `WIRELESS_REGDOM="<CC>"` in `/etc/conf.d/wireless-regdom`), otherwise the
  AX210 runs on the restrictive world domain.

```sh
sudo install -Dm644 system/etc/modprobe.d/btusb-no-autosuspend.conf /etc/modprobe.d/
```

**Verify.** `cat /sys/module/btusb/parameters/enable_autosuspend` (`N`),
`iw dev` / `iw dev <if> get power_save`, `iw reg get`.

## 12. Suspend, hibernate, shutdown

- **Sleep is s2idle only** (`/sys/power/mem_sleep` = `[s2idle]`; the firmware has
  no S3). It works very well: over a 2 h 46 min sleep in a bag, 99.95 % of the time
  was spent in hardware sleep and the battery drew roughly 0.2 W. Lid and power
  button suspend (PowerDevil, [05 section 11](05-dotfiles-and-desktop.md#11-power-related-user-settings)).
  The dGPU being off (section 4) is likely a big part of that.
- **Hibernate is masked** and should stay so on this model:

  ```sh
  sudo systemctl mask hibernate.target suspend-then-hibernate.target \
      systemd-hibernate.service systemd-suspend-then-hibernate.service
  ```

  Both hibernate modes fail here: with `HibernateMode=platform` the image is
  written but the machine never powers off (screen black, keyboard light on;
  the same ACPI S4 hang is reported on other AMD laptops); with `shutdown` it
  powers off, but amdgpu fails to restore (`gfx_v11_0` / `mes_kiq` ring test
  -110, garbage on screen). Two leftovers from those attempts
  (`/etc/systemd/sleep.conf.d/10-suspend-then-hibernate.conf` and
  `/etc/tmpfiles.d/hibernate-image-size.conf`) still exist on the reference
  machine but have no effect while hibernate is masked; they are not shipped.
- Verify suspend quality after a sleep:

  ```sh
  cat /sys/power/suspend_stats/last_hw_sleep    # microseconds in hardware sleep
  journalctl -b -g 'PM: suspend'
  ```

  `last_hw_sleep` is more trustworthy than `amd_pmc`'s `s0ix_stats` here.
- Shutdown: no workarounds are in place. The NVMe drive reports some "unsafe
  shutdowns" in SMART; at ~3.6 % of power cycles and with zero media errors that
  is consistent with occasional forced power-offs during kernel work, not a fault.
- `nvidia-suspend`, `nvidia-resume` and `nvidia-hibernate` services are enabled
  (they matter in Hybrid mode; see the `PreserveVideoMemoryAllocations` note in
  section 4).

## 13. Copilot key

The Copilot key sends Shift+Super+F23. xkeyboard-config maps that to
`XF86Assistant`, which Qt 6 does not know, so KDE cannot bind it. A small XKB
option turns it into plain F19, bindable as Meta+Shift+F19:

- [`home/.config/xkb/symbols/copilot`](../home/.config/xkb/symbols/copilot),
  [`home/.config/xkb/rules/evdev`](../home/.config/xkb/rules/evdev)
- [`home/.config/plasma-workspace/env/xkb-copilot.sh`](../home/.config/plasma-workspace/env/xkb-copilot.sh)
  adds `custom:copilot` to `XKB_DEFAULT_OPTIONS` (KWin reads the option from the
  environment, not from `kxkbrc`).

```sh
install -Dm644 home/.config/xkb/symbols/copilot ~/.config/xkb/symbols/copilot
install -Dm644 home/.config/xkb/rules/evdev ~/.config/xkb/rules/evdev
install -Dm644 home/.config/plasma-workspace/env/xkb-copilot.sh ~/.config/plasma-workspace/env/
# log out and in, then bind the key in System Settings > Shortcuts
```

**Revert.** Delete the three files and log in again.

## 14. Watchers

Two small user-level watchers; they only read and notify.

**`dmub-watch` / `dmub-check`** ([`home/.local/bin/`](../home/.local/bin/),
[`dmub-watch.service`](../home/.config/systemd/user/dmub-watch.service)). On the
patched kernel a DMUB hang becomes a timeout and an error line instead of a
freeze - which also makes it silent. `dmub-watch` follows the kernel journal,
saves five minutes of context to `~/.local/state/dmub-watch/` and sends a
critical notification when one of those lines appears. It never reads debugfs
(reading the PSR/Replay files sends DMUB commands). `dmub-check` summarises the
last five boots. On the reference machine no event has been recorded since the
watcher was installed.

**`stuck-watch`** ([`stuck-watch`](../home/.local/bin/stuck-watch),
[`.service`](../home/.config/systemd/user/stuck-watch.service),
[`.timer`](../home/.config/systemd/user/stuck-watch.timer), every 5 min). Notifies
about processes stuck in D state across two runs, kernel hung-task warnings, and
the NVIDIA card being in D0 while `supergfxctl -g` reports Integrated - the
symptoms of the `nvidia-powerd` hang described in section 3. On battery it adds
the current power draw. `stuck-watch --show` prints the state.

```sh
install -Dm755 -t ~/.local/bin home/.local/bin/{dmub-watch,dmub-check,stuck-watch}
install -Dm644 -t ~/.config/systemd/user home/.config/systemd/user/{dmub-watch.service,stuck-watch.service,stuck-watch.timer}
systemctl --user daemon-reload
systemctl --user enable --now dmub-watch.service stuck-watch.timer
```

Both expect `ACAD` / `BAT1` power supply names and `supergfxctl`; adjust for other
models. **Revert.** `systemctl --user disable --now dmub-watch.service stuck-watch.timer`.

## 15. Measured numbers

Measured on this machine, on battery, Bluetooth off, speakers muted, fixed
brightness, idle dark desktop, unless noted. Each comparison was A/B/A; differences
below ~0.15 W are noise.

| Change | Effect |
| --- | --- |
| Panel Replay working (patch 0003) | idle 4.62 -> 3.87 W |
| Lazy RCU | idle 3.87 -> ~3.77 W; local timer IRQs ~400 -> ~210 /s |
| 120 Hz -> 60 Hz | about -0.45 W idle |
| VRR Always (without Replay) | about -0.35 W idle |
| VRR Always (with Replay) | about +0.4 W idle |
| NMI watchdog off | about -0.13 W (noise floor) |
| HDR off | about -0.2 W |
| Dark vs white full-screen content | about 1.4 W (OLED: by far the largest lever) |
| Brightness 100 % -> 20 % on a dark desktop | about -0.25 W |
| Panel off entirely | SoC base ~3.9-4.1 W does not move with any display setting |
| s2idle | ~0.2 W |

Best idle result with the current kernel: **about 3.8 W at 120 Hz**. Video:
about 6.6-6.8 W in mpv with hardware decoding, about 7.3 W fullscreen in a
Chromium-based browser. These figures were taken with the patched KWin 6.8.0
(see [04](04-custom-packages.md#kwin-lapidary)); the current patched 6.8.1 build
has not been re-measured.

Measurement tips: KDE's automatic brightness (ambient light sensor) pulls the
backlight back within seconds - disable it before measuring. Use
`/sys/class/power_supply/BAT1/{current_now,voltage_now}` averaged over minutes,
keep Bluetooth off (a headset connecting mid-test changes everything) and do a
short dry run first.

## 16. Tried and dropped

Everything here was installed or configured at some point and has been removed
or disabled; the system was checked to confirm it.

| Item | Why it was dropped |
| --- | --- |
| **TLP** (and `tlp-pd`, `tlpui`) | Replaced by plain power-profiles-daemon. The charge limit already belongs to asusd; TLP's extras (USB denylist, Wi-Fi power save off) were consciously given up. TLP's `SAV` profile had also pinned the iGPU at 600 MHz. |
| **bpftune** | Retunes TCP congestion control and netdev budgets - no measurable benefit on a Wi-Fi laptop client, and 7-9 s of CPU at boot loading BPF programs. Changed sysctls were reset to kernel defaults. |
| **sched-ext (`scx_lavd` via `scx_loader`)** | Its power benefit was never measured (with amd-pstate-epp there is no schedutil, so scx cannot steer frequency; only core packing is left), and after hours of uptime lavd caused 200-500 ms kworker wakeup latencies - visible cursor stutter (upstream scx issue 3739). Back to the kernel scheduler. |
| **`teo` cpuidle governor** | Package power went up (RAPL 0.52 -> 0.75 W) in A/B/A. `menu` stays. |
| **ananicy-cpp + rules** | Removed; no measurable gain. |
| **cardwire** (eBPF-based dGPU access control) and **zephyrusctl** | Kept the dGPU in Hybrid mode but hidden from applications. Worked, but brought boot-order races (`/dev/nvidia0` not yet present), wake-ups from monitoring calls, and the HDMI-on-dGPU problem. Stock supergfxctl in Integrated mode is simpler. zephyrusctl lives on at [github.com/lckt0/zephyrusctl](https://github.com/lckt0/zephyrusctl). |
| **Hibernate / suspend-then-hibernate** | See section 12: both modes fail on this model. Masked. |
| **PipeWire "all Bluetooth headphones" combine sink** | Not used; removed. |
| **`amdgpu.dcfeaturemask` to enable PSR** | Has no effect on DCN 3.5 (not read for PSR), and PSR-SU is hard-disabled in the driver. |
| **`KWIN_DRM_USE_COLOR_PIPELINE=1`** | Made it impossible to put video on an overlay plane; five days of "overlays don't work on AMD" turned out to be this variable. |
| **VRR "Always" as default** | Overlay windows vanish on cursor movement (driver bug, fix not applied), and with Replay it costs power. |
| **`nvidia-powerd.service`** (NVIDIA Dynamic Boost) | Failed on every boot (`start-limit-hit` in Integrated mode, `Allocate Root client failed 0x59` with the module loaded); Dynamic Boost does not work with this dGPU/firmware. Disabled. |
| **asusd toggling nvidia-powerd** (`disable_nvidia_powerd_on_battery: true`) | Restarting nvidia-powerd on AC after resume loaded the NVIDIA module past the blacklist and hung it. |
| **Patched KWin 6.7.5** (direct-scanout CRTC degamma handling, cursor async-commit throttling) | Superseded by KWin 6.8; the version pinning of the patched package also blocked Plasma updates. The current KWin patch is in [04](04-custom-packages.md#kwin-lapidary). |
| **Wi-Fi / NVMe runtime PM forced to `auto`** | No measurable gain. |
| **Local WirePlumber `alsa.lua` override** | Based on 0.5.17 and shadowed the fixes in 0.5.18 (section 10). Removed; the packaged ALSA monitor is used. |
| **EasyEffects with DeepFilterNet on the microphone** | The highest wakeup source on the system, but closing it saved only ~0.12 W. Not part of the power setup; the package is still installed. |
