#!/usr/bin/env python3
"""Regenerate the cachy-update tray/notification icons with the Arch logo.

cachy-update (the arch-update fork shipped by CachyOS) uses CachyOS-logo icons
named cachy-update-{blue,dark,light} and
cachy-update_updates-available-{blue,dark,light}[-cb]. Icons with the same
names in ~/.local/share/icons/hicolor/scalable/apps take precedence over
/usr/share, so the package itself is not modified.

The Arch logo path is taken from /usr/share/pixmaps/archlinux-logo.svg
(package filesystem); the status badge (check mark,
download circle, colours, colour-blind variant) is copied from the original
icons, and the logo is masked around the badge.

Usage: gen-arch-update-icons.py <output-dir>
Run it again if a cachy-update release adds or renames icons.
"""
import os
import re
import sys

SRC = "/usr/share/icons/hicolor/scalable/apps"
OUT = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
os.makedirs(OUT, exist_ok=True)
logo = open("/usr/share/pixmaps/archlinux-logo.svg").read()
arch_d = re.search(r'<path d="(m127\.98[^"]+)"', logo).group(1)
# Arch logo main path bbox is about x 11.3..226.1, y 12.07..243.9 (256 viewBox)
S = 0.08
names = sorted(f for f in os.listdir(SRC) if f.startswith("cachy-update") and f.endswith(".svg"))
for n in names:
    src = open(os.path.join(SRC, n)).read()
    light = "-light" in n
    blue = "-blue" in n
    dx = 0.2909 if light else 0.0     # the badge is shifted right by 0.2909 in the light variant
    cx = 17 + dx
    fill = "#1793d1" if blue else ("#fff" if light else "#000")
    # badge: every path whose d starts with "M17" (fill + gradient layer if any)
    badges = re.findall(r'<path[^>]*d="M17[^"]*"[^>]*/>', src)
    assert badges, n
    styles = dict(re.findall(r'\.(st\d+)\{fill:(#[0-9a-fA-F]+)\}', src))
    badges = [re.sub(r'class="(st\d+)"', lambda m: f'fill="{styles[m.group(1)]}"', b) for b in badges]
    defs = ""
    if any("linear-gradient8" in b for b in badges):
        defs = re.search(r'<linearGradient id="linear-gradient8".*?</linearGradient>', src).group(0)
    tx = 10.0 + dx - 118.7 * S
    ty = 2.75 - 12.07 * S
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs>' + defs +
        '<mask id="notch" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">'
        '<rect width="24" height="24" fill="#fff"/>'
        f'<circle cx="{cx:.4f}" cy="16" r="6" fill="#000"/>'
        f'<rect x="{cx:.4f}" y="16" width="8" height="8" fill="#000"/></mask></defs>'
        f'<g mask="url(#notch)"><path fill="{fill}" fill-rule="evenodd" '
        f'transform="translate({tx:.4f} {ty:.4f}) scale({S})" d="{arch_d}"/></g>'
        + "".join(badges) + "</svg>\n"
    )
    open(os.path.join(OUT, n), "w").write(svg)
    print(n, len(badges))
