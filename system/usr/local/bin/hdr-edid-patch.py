#!/usr/bin/env python3
"""
Copy the Colorimetry and HDR Static Metadata data blocks out of the CTA-861
blocks embedded in a DisplayID 2.0 extension, and append them to the EDID as a
separate top-level CTA-861 extension block, so that libdisplay-info 0.3.x (and
therefore KWin) can see them.

Usage: ./hdr-edid-patch.py <input.bin> <output.bin>
"""
import sys


def displayid_cta_payload(ext: bytes) -> bytes:
    """Payload of the 0x81 (CTA) data blocks inside a DisplayID extension."""
    if len(ext) < 6 or ext[0] != 0x70:
        return b""
    out = b""
    pos, end = 5, min(5 + ext[2], len(ext))
    while pos + 3 <= end:
        tag, length = ext[pos], ext[pos + 2]
        if tag == 0x81:
            out += ext[pos + 3:pos + 3 + length]
        pos += 3 + length
    return out


def pick_cta_blocks(payload: bytes) -> bytes:
    """Only the Colorimetry (0x05) and HDR Static Metadata (0x06) blocks."""
    out = b""
    pos = 0
    names = {0x05: "Colorimetry", 0x06: "HDR Static Metadata"}
    while pos < len(payload):
        tag, length = payload[pos] >> 5, payload[pos] & 0x1F
        blk = payload[pos:pos + 1 + length]
        if tag == 7 and length >= 1 and blk[1] in names:
            out += blk
            print(f"  found: {names[blk[1]]} ({length} bytes)")
        pos += 1 + length
    return out


def checksum(data: bytes) -> int:
    return (-sum(data)) & 0xFF


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip())
    edid = open(sys.argv[1], "rb").read()
    if not edid or len(edid) % 128:
        sys.exit("EDID length is not a multiple of 128")
    blocks = [edid[i:i + 128] for i in range(0, len(edid), 128)]

    payload = b"".join(displayid_cta_payload(b) for b in blocks[1:])
    if not payload:
        sys.exit("no CTA (0x81) data block found inside DisplayID")

    keep = pick_cta_blocks(payload)
    if not keep:
        sys.exit("no Colorimetry / HDR Static Metadata block found")

    cta = bytearray(128)
    cta[0] = 0x02                    # CTA-861 extension tag
    cta[1] = 0x03                    # revision 3
    cta[2] = 4 + len(keep)           # DTD offset (no DTDs)
    cta[3] = 0x00                    # no native DTD, no basic audio
    cta[4:4 + len(keep)] = keep
    cta[127] = checksum(cta[:127])

    base = bytearray(blocks[0])
    base[126] = len(blocks)          # one more extension block
    base[127] = checksum(base[:127])

    out = bytes(base) + b"".join(blocks[1:]) + bytes(cta)
    open(sys.argv[2], "wb").write(out)
    print(f"written: {sys.argv[2]} ({len(out)} bytes)")


main()
