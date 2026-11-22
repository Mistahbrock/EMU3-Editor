#!/usr/bin/env python3 -I
"""Builds a synthetic E4B bank (TOC1 + 2 samples + 1 preset) for round-trip tests. Not a real-sampler file."""
import struct, math, sys
def be32(v): return struct.pack('>I', v)
def sample_chunk(num, name, rate, loop, frames):
    pad = [0]*4
    pcm = pad + [int(12000*math.sin(i*0.05)) for i in range(frames)] + pad
    n = len(pcm); base = 92
    h = bytearray(94)
    struct.pack_into('>H', h, 0, num)
    h[2:18] = name.ljust(16).encode('latin1')
    struct.pack_into('<IIII', h, 0x16, base, base, base+(n-1)*2, base+(n-1)*2)
    ls, le = loop
    struct.pack_into('<IIII', h, 0x26, base+(ls+4)*2, base+(ls+4)*2, base+(le+4)*2, base+(le+4)*2)
    struct.pack_into('<I', h, 0x36, rate)
    struct.pack_into('<H', h, 0x3C, 0x20|0x01|0x08)
    return bytes(h) + struct.pack('<%dh' % n, *pcm)
def preset_chunk(num, name):
    d = bytearray(400); struct.pack_into('>H', d, 0, num); d[2:18] = name.ljust(16).encode('latin1'); return bytes(d)
def chunk(cid, data):
    c = cid.encode() + be32(len(data)) + data
    return c + (b'\0' if len(data) & 1 else b'')
body = [('E4P1', preset_chunk(0, 'Test Preset'), 'Test Preset'),
        ('E3S1', sample_chunk(1, 'Sine A', 44100, (100, 900), 1000), 'Sine A'),
        ('E3S1', sample_chunk(2, 'Sine B', 22050, (50, 400), 500), 'Sine B')]
toc_len = 32*len(body)
off = 12 + 8 + toc_len
toc = b''
for i, (cid, data, name) in enumerate(body):
    toc += cid.encode() + be32(len(data)) + be32(off) + struct.pack('>H', i+1) + name.ljust(16).encode() + b'\0\0'
    off += 8 + len(data) + (len(data) & 1)
payload = b'E4B0' + chunk('TOC1', toc) + b''.join(chunk(c, d) for c, d, _ in body)
open(sys.argv[1], 'wb').write(b'FORM' + be32(len(payload)) + payload)
