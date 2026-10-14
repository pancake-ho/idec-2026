"""Parse this dataset's AVC onDemand SegmentBase MPD and actual ISO-BMFF SIDX."""
from dataclasses import dataclass, asdict
from fractions import Fraction
import struct
import xml.etree.ElementTree as ET
from urllib.parse import urljoin

@dataclass(frozen=True)
class Representation:
    index: int
    id: str
    width: int
    height: int
    bandwidth: int
    fps: float
    url: str
    index_start: int
    index_end: int

def parse_mpd(path, url):
    root = ET.parse(path).getroot(); ns = {'m': root.tag.split('}')[0][1:]}
    if root.get('type') != 'static' or 'on-demand' not in root.get('profiles', ''):
        raise ValueError('static ISO onDemand MPD required')
    periods = root.findall('m:Period', ns)
    if len(periods) != 1:
        raise ValueError('one Period required')
    rows = []
    for a in periods[0].findall('m:AdaptationSet', ns):
        for r in a.findall('m:Representation', ns):
            codec = r.get('codecs', a.get('codecs', ''))
            if not codec.startswith(('avc1', 'avc3')):
                continue
            base, seg = r.find('m:BaseURL', ns), r.find('m:SegmentBase', ns)
            if base is None or seg is None or not seg.get('indexRange'):
                raise ValueError('AVC Representation requires BaseURL and SegmentBase indexRange')
            b0 = root.find('m:BaseURL', ns); b1 = periods[0].find('m:BaseURL', ns); b2 = a.find('m:BaseURL', ns)
            resolved = url
            for b in (b0, b1, b2, base):
                if b is not None:
                    resolved = urljoin(resolved, b.text.strip())
            begin, end = map(int, seg.get('indexRange').split('-'))
            rows.append(dict(id=r.get('id'), width=int(r.get('width')), height=int(r.get('height')),
                             bandwidth=int(r.get('bandwidth')), fps=float(Fraction(r.get('frameRate', a.get('frameRate', '24')))),
                             url=resolved, index_start=begin, index_end=end))
    rows.sort(key=lambda r: r['bandwidth'])
    if not rows:
        raise ValueError('no AVC representations')
    return [Representation(index=i, **r) for i, r in enumerate(rows)]

def parse_sidx(data, absolute_start=0):
    """Resolve direct references. Offsets are absolute bytes; duration is never bitrate-derived."""
    pos = 0
    while pos + 8 <= len(data):
        size, kind = struct.unpack_from('>I4s', data, pos); header = 8
        if size == 1:
            size = struct.unpack_from('>Q', data, pos + 8)[0]; header = 16
        if size == 0:
            size = len(data) - pos
        if size < header or pos + size > len(data):
            raise ValueError('truncated ISO box')
        if kind != b'sidx':
            pos += size; continue
        q = pos + header; version = data[q]; q += 4
        if version not in (0, 1):
            raise ValueError('unknown SIDX version')
        _, scale = struct.unpack_from('>II', data, q); q += 8
        if not scale:
            raise ValueError('zero SIDX timescale')
        fmt = '>II' if version == 0 else '>QQ'
        earliest, first = struct.unpack_from(fmt, data, q); q += struct.calcsize(fmt)
        _, count = struct.unpack_from('>HH', data, q); q += 4
        offset = absolute_start + pos + size + first; ticks = earliest; result = []
        if q + count * 12 > pos + size:
            raise ValueError('truncated SIDX entries')
        for i in range(count):
            length, duration, sap = struct.unpack_from('>III', data, q); q += 12
            if length >> 31:
                raise ValueError('hierarchical SIDX unsupported; do not invent segment durations')
            length &= 0x7fffffff
            if not length or not duration:
                raise ValueError('empty segment')
            result.append(dict(segment_index=i, start=ticks / scale, duration=duration / scale,
                               offset=offset, size_bytes=length, starts_with_sap=bool(sap >> 31)))
            ticks += duration; offset += length
        return result
    raise ValueError('SIDX absent at MPD indexRange')

def local_segments(path, rep):
    with open(path, 'rb') as f:
        f.seek(rep.index_start); data = f.read(rep.index_end - rep.index_start + 1)
    rows = parse_sidx(data, rep.index_start)
    if any(r['offset'] + r['size_bytes'] > __import__('os').path.getsize(path) for r in rows):
        raise ValueError('SIDX references exceed media file')
    if any(abs(r['duration'] - 2) > 1 / rep.fps + 1e-6 for r in rows[:-1]):
        raise ValueError('this configuration requires 2-second segments; final short segment allowed')
    return rows
