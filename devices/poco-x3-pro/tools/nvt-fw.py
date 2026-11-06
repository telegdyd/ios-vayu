#!/usr/bin/env python3
"""The Novatek NT36675 touch firmware of vayu, out of the phone's own Android kernel.

On MIUI 14 (V14.0.3.0.TJUMIXM) j20s_novatek_ts_fw01/02.bin (and the mp01/02 test images) are not files on
vendor, odm or modem: the kernel carries them built in. Its nt36xxx driver keeps a table of entries
{name, ..., data, ...} pointing at the names and at the images in the kernel's .rodata. This reads a
boot.img (header v0-v2, the arm64 Image raw or gzip), finds each name's string, every 8-byte pointer to it,
and among the next qwords a pointer to a blob that passes vayu_nvt.c's own checks (an "NVT"/"MOD" end flag
on a 4 KiB sector, FW_VER + ~FW_VER = 0xff at the start of that sector, ILM/DLM inside the image), and
writes the image up to that end flag.

usage: nvt-fw.py boot.img OUTDIR        (nothing is written to the phone; boot.img is a copy)
"""
import gzip
import hashlib
import os
import re
import struct
import sys


def kernel(img):
    if img[:8] != b'ANDROID!':
        return img                       # already a kernel Image
    ksize, = struct.unpack_from('<I', img, 8)
    page, = struct.unpack_from('<I', img, 36)
    k = img[page:page + ksize]
    return gzip.decompress(k) if k[:2] == b'\x1f\x8b' else k


def nvt_size(b):
    """the image's length: its first 4 KiB sector ending in the "NVT"/"MOD" flag with a good version bar
    (vayu_nvt.c nvt_fw_parse() looks from the file's end; here the images lie back to back in the kernel,
    so from the start), or 0"""
    for i in range(1, len(b) // 4096 + 1):
        need = i * 4096
        if b[need - 3:need] in (b'NVT', b'MOD') and (b[need - 4096] + b[need - 4095]) & 0xff == 0xff:
            break
    else:
        return 0
    for i in range(2):
        binoff, _sram, size = struct.unpack_from('<III', b, 12 * i)
        if not 0 < binoff + size <= need:
            return 0
    return need


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    k = kernel(open(sys.argv[1], 'rb').read())
    out = sys.argv[2]
    text_offset, = struct.unpack_from('<Q', k, 8)
    if k[56:60] != b'ARM\x64':
        sys.exit('nvt-fw.py: not an arm64 kernel Image')
    found = {}
    for base in (0xffffff8008000000 + text_offset, 0xffffffc010000000, 0xffffffc008000000 + text_offset):
        for m in re.finditer(rb'\x00(j20s_novatek_ts_(?:fw|mp)0[12]\.bin)\x00', k):
            name, va = m.group(1).decode(), base + m.start() + 1
            for r in re.finditer(re.escape(struct.pack('<Q', va)), k):
                o = r.start()
                if o % 8:
                    continue
                for j in range(1, 6):
                    d, = struct.unpack_from('<Q', k, o + 8 * j)
                    doff = d - base
                    if 0 <= doff < len(k) - 4096:
                        n = nvt_size(k[doff:doff + (1 << 20)])
                        if n and name not in found:
                            found[name] = k[doff:doff + n]
        if found:
            break
    if not found:
        sys.exit('nvt-fw.py: no Novatek images found in this kernel')
    os.makedirs(out, exist_ok=True)
    for name, blob in sorted(found.items()):
        open(os.path.join(out, name), 'wb').write(blob)
        print('nvt-fw.py: %s %d bytes, FW_VER %d, sha256 %s' % (name, len(blob), blob[len(blob) - 4096],
                                                           hashlib.sha256(blob).hexdigest()))


main()
