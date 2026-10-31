#!/usr/bin/env python3
"""Read-only JPEG metadata census: prints dimensions, APP segments, EXIF tags (names only), GPS/thumbnail presence.
   host-run docker-ws/jpeg_meta.py <file.jpg>...   (prints no tag values except Orientation)"""
import struct, sys

TAGS = {0x010F:'Make',0x0110:'Model',0x0112:'Orientation',0x0132:'DateTime',0x8769:'ExifIFD',0x8825:'GPSIFD',
        0x9003:'DateTimeOriginal',0x9004:'DateTimeDigitized',0x927C:'MakerNote',0x0131:'Software',0x013B:'Artist',
        0x8298:'Copyright',0x0201:'JPEGInterchangeFormat',0x0202:'JPEGInterchangeFormatLength',0xA420:'ImageUniqueID',
        0xA002:'PixelXDimension',0xA003:'PixelYDimension',0x011A:'XResolution',0x011B:'YResolution',0x0128:'ResolutionUnit',
        0x0213:'YCbCrPositioning',0xA005:'InteropIFD',0x9010:'OffsetTime',0x9011:'OffsetTimeOriginal'}

def ifd(buf, off, endian, names, depth=0):
    if off + 2 > len(buf): return None
    n = struct.unpack(endian + 'H', buf[off:off+2])[0]
    for i in range(n):
        e = off + 2 + 12 * i
        if e + 12 > len(buf): break
        tag, typ, cnt, val = struct.unpack(endian + 'HHII', buf[e:e+12])
        name = TAGS.get(tag, '0x%04X' % tag)
        if tag == 0x0112:
            v = struct.unpack(endian + 'H', buf[e+8:e+10])[0]; name += '=%d' % v
        names.append(('  ' * depth) + name)
        if tag in (0x8769, 0xA005) and depth < 2: ifd(buf, val, endian, names, depth + 1)
        if tag == 0x8825: names.append(('  ' * depth) + '  GPS entries=%d' % struct.unpack(endian + 'H', buf[val:val+2])[0] if val + 2 <= len(buf) else '  GPS?')
    nxt = off + 2 + 12 * n
    return struct.unpack(endian + 'I', buf[nxt:nxt+4])[0] if nxt + 4 <= len(buf) else 0

def census(path):
    d = open(path, 'rb').read()
    out = {'file': path.split('/')[-1], 'bytes': len(d), 'segments': [], 'exif': [], 'ifd1_thumbnail': False}
    if d[:2] != b'\xff\xd8': out['error'] = 'not a JPEG (magic %r)' % d[:12]; return out
    i = 2
    while i < len(d) - 4:
        if d[i] != 0xFF: i += 1; continue
        m = d[i+1]
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7: i += 2; continue
        if m == 0xD9: break
        ln = struct.unpack('>H', d[i+2:i+4])[0]; seg = d[i+4:i+2+ln]
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack('>HH', seg[1:5]); out['dims'] = '%dx%d' % (w, h); out['sof'] = 'SOF%d' % (m - 0xC0)
        if m == 0xDA: out['segments'].append('SOS'); break
        label = 'APP%d' % (m - 0xE0) if 0xE0 <= m <= 0xEF else ('COM' if m == 0xFE else ('DQT' if m == 0xDB else ('DHT' if m == 0xC4 else 'M%02X' % m)))
        if m == 0xE1 and seg[:6] == b'Exif\x00\x00':
            label = 'APP1-Exif'; t = seg[6:]; endian = '<' if t[:2] == b'II' else '>'
            first = struct.unpack(endian + 'I', t[4:8])[0]
            nxt = ifd(t, first, endian, out['exif'])
            if nxt: out['ifd1_thumbnail'] = True; ifd(t, nxt, endian, out['exif'], 1)
        elif m == 0xE1 and b'http://ns.adobe.com/xap' in seg[:40]: label = 'APP1-XMP'
        elif m == 0xE2 and seg[:12] == b'ICC_PROFILE\x00': label = 'APP2-ICC'
        elif m == 0xED: label = 'APP13-IPTC/Photoshop'
        elif m == 0xE0 and seg[:5] == b'JFIF\x00': label = 'APP0-JFIF'
        elif m == 0xEE: label = 'APP14-Adobe'
        out['segments'].append(label)
        i += 2 + ln
    return out

for p in sys.argv[1:]:
    r = census(p)
    print('== %s bytes=%s dims=%s %s' % (r['file'], r['bytes'], r.get('dims'), r.get('sof', r.get('error', ''))))
    print('   segments:', ' '.join(r['segments']))
    print('   exif:', ', '.join(x.strip() for x in r['exif']) or 'none', '| ifd1_thumbnail=%s' % r['ifd1_thumbnail'])
