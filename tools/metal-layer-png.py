#!/usr/bin/env python3
"""metal-layer-png.py RAW PNG [SCALE]: metal_layer's capture (u32 width, height, bytes per row; BGRA rows) as a PNG,
every SCALE-th pixel (default 2)."""
import struct, sys, zlib
raw, out = sys.argv[1], sys.argv[2]
step = int(sys.argv[3]) if len(sys.argv) > 3 else 2
data = open(raw, 'rb').read()
w, h, row = struct.unpack('<III', data[:12])
px = data[12:]
ow, oh = (w + step - 1) // step, (h + step - 1) // step
rows = bytearray()
for y in range(0, h, step):
    line = px[y * row:y * row + w * 4]
    rgb = bytearray(ow * 3)
    b, g, r = line[0::4][::step], line[1::4][::step], line[2::4][::step]
    rgb[0::3], rgb[1::3], rgb[2::3] = r, g, b
    rows += b'\0' + rgb
def chunk(k, body):
    return struct.pack('>I', len(body)) + k + body + struct.pack('>I', zlib.crc32(k + body))
open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', ow, oh, 8, 2, 0, 0, 0)) +
                      chunk(b'IDAT', zlib.compress(bytes(rows), 6)) + chunk(b'IEND', b''))
print(f'{out}: {ow}x{oh} from {w}x{h}')
