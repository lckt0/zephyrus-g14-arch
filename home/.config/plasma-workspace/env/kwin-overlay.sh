# Sourced by plasma-workspace before KWin starts (any *.sh in this directory).
# G14 / amdgpu settings for hardware overlay planes (the Linux equivalent of
# Windows MPO) and direct scanout. See docs/03-g14-hardware-and-power.md.

# Use hardware overlay planes. KWin enables them by default only on Intel;
# on amdgpu they must be requested explicitly.
export KWIN_USE_OVERLAYS=1

# Keep scanout buffers at 32 bpp instead of letting KWin fall back to FP16
# (AB48, 64 bpp). Measured: ~41.5 MB -> ~21 MB per frame, i.e. ~5 GB/s ->
# ~2.5 GB/s of scanout traffic at 120 Hz.
# 30 rather than 24: with 24, KWin sometimes picks RA24 (RGBA8888) for a layer
# buffer. amdgpu advertises RA24 with DCC but then rejects it at addfb
# ("non-zero modifier for unused plane 1"; RGBA8888 is missing from the DCC
# format table, mainline too). On that frame the window layer is dropped and
# the desktop flashes while a popup closes. With 30 KWin picks AR30/AB30
# (still 32 bpp, and in the DCC table).
export KWIN_DRM_PREFER_COLOR_DEPTH=30

# Keep per-plane colour pipelines OFF (=0; never set this to 1 here).
# - With a colour pipeline on a plane, KWin refuses YUV content on it
#   (drm_pipeline.cpp: colorPipeline.isValid() && yuvCoefficients() != Identity
#   -> InvalidArguments), so video can never go to an overlay plane.
# - KWin 6.8.0 enabled it by default; AMD's per-plane LUTs are low resolution
#   and game/video colours were visibly wrong (KDE bug 525839). 6.8.1 turned the
#   default off again (commit 01222b41cb), so on 6.8.1+ this line is redundant
#   but harmless.
export KWIN_DRM_USE_COLOR_PIPELINE=0
