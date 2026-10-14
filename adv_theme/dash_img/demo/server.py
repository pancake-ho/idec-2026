#!/usr/bin/env python3
"""Offline-first BBB interactive demo. Python stdlib only; bound to loopback by default.

This app switches among actual DASH dataset AVC representations and demonstrates a
bandwidth-budget selection policy. It is NOT a DASH ABR client or traffic shaper.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import re
import sys
import xml.etree.ElementTree as ET
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
STATIC = Path(__file__).resolve().parent / "static"


def iso_seconds(value: str) -> float:
    m = re.fullmatch(r"PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?", value)
    if m is None:
        raise ValueError("Unsupported ISO-8601 duration: " + value)
    return float(m.group(1) or 0)*3600 + float(m.group(2) or 0)*60 + float(m.group(3) or 0)


def read_mpd(mpd: Path) -> dict:
    doc = ET.parse(mpd).getroot()
    ns = {"m": "urn:mpeg:dash:schema:mpd:2011"}
    period = doc.find('m:Period', ns)
    if period is None:
        raise ValueError('Period absent in MPD')
    duration = iso_seconds(doc.get('mediaPresentationDuration') or period.get('duration', 'PT0S'))
    if duration <= 0:
        raise ValueError('Invalid MPD duration')
    reps = []
    for adap in period.findall('m:AdaptationSet', ns):
        for r in adap.findall('m:Representation', ns):
            if not (r.get('codecs') or adap.get('codecs') or '').startswith(('avc1', 'avc3')):
                continue
            fps_str = r.get('frameRate') or adap.get('maxFrameRate') or '24'
            if '/' in fps_str:
                numerator, denominator = map(int, fps_str.split('/'))
                fps = numerator / denominator
            else:
                fps = float(fps_str)
            reps.append({
                'name': r.get('id', ''),
                'bandwidth': int(r.attrib['bandwidth']),
                'width': int(r.attrib['width']),
                'height': int(r.attrib['height']),
                'fps': fps,
            })
    reps.sort(key=lambda x: x['bandwidth'])
    if not reps:
        raise ValueError('AVC video representations absent')
    if len({r['bandwidth'] for r in reps}) != len(reps):
        raise ValueError('Identical bandwidths: ambiguous representation mapping')
    for i, r in enumerate(reps):
        r['index'] = i
        r['kbps'] = round(r['bandwidth'] / 1000.0, 3)
        r['url'] = f'/media/{i}'
    return {'duration': duration, 'fps': reps[0]['fps'], 'segmentSeconds': 2,
            'representations': reps}


def media_status(path: Path, require_receipt: bool) -> str:
    if not path.is_file():
        return 'DOWNLOADING' if Path(str(path) + '.part').exists() else 'MISSING'
    if path.stat().st_size < 4096:
        return 'INCOMPLETE'
    receipt = Path(str(path) + '.receipt.json')
    if receipt.exists():
        try:
            saved = json.loads(receipt.read_text(encoding='utf-8'))
            if int(saved['size_bytes']) != path.stat().st_size:
                return 'SIZE_MISMATCH'
        except (OSError, ValueError, KeyError, TypeError):
            return 'INVALID_RECEIPT'
        return 'READY'
    return 'NO_RECEIPT' if require_receipt else 'READY_UNVERIFIED'


def build_catalog(root: Path, media_work: Path, mpd: Path, require_receipt: bool = True) -> tuple[dict, dict[int, Path]]:
    catalog = read_mpd(mpd)
    basedir = media_work / 'media' / 'bbb'
    lookup = {}
    for rep in catalog['representations']:
        idx = rep['index']
        path = basedir / f'rep_{idx:02d}.mp4'
        status = media_status(path, require_receipt)
        ready = status.startswith('READY')
        rep['available'] = ready
        rep['status'] = status
        rep['sizeBytes'] = path.stat().st_size if ready else None
        if ready:
            lookup[idx] = path
    catalog['dataset'] = 'BigBuckBunny · AVC 2-second onDemand'
    catalog['availableCount'] = len(lookup)
    catalog['mediaRoot'] = str(basedir)
    catalog['notice'] = '실제 MP4 표현본 교체 시연 · Network Budget 선택은 정책 시뮬레이션 (실제 대역폭 제한 아님)'
    return catalog, lookup


class DemoServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, catalog, lookup):
        self.catalog, self.lookup = catalog, lookup
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'BBB-Demo/1.0'

    def do_HEAD(self):
        self.route(head_only=True)

    def do_GET(self):
        self.route(head_only=False)

    def log_message(self, fmt, *args):
        # Ignore noisy successful range requests; surface failures.
        if args and str(args[1]) not in ('200', '206'):
            super().log_message(fmt, *args)

    def fail(self, status: int, message: str, head_only: bool):
        b = json.dumps({'error': message}).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        if not head_only:
            self.wfile.write(b)

    def body(self, data: bytes, content_type: str, head_only: bool, cache: str = 'no-store'):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', cache)
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        if not head_only:
            self.wfile.write(data)

    def route(self, head_only: bool):
        path = urlparse(self.path).path
        if path == '/api/manifest':
            self.body(json.dumps(self.server.catalog, ensure_ascii=False).encode('utf-8'),
                      'application/json; charset=utf-8', head_only)
            return
        if path == '/api/health':
            self.body(json.dumps({'status': 'ok', 'available': self.server.catalog['availableCount']}).encode('utf-8'),
                      'application/json', head_only)
            return
        match = re.fullmatch(r'/media/(\d{1,3})', path)
        if match:
            idx = int(match.group(1))
            if idx not in self.server.lookup:
                self.fail(404, 'Representation not downloaded', head_only)
                return
            self.video(self.server.lookup[idx], head_only)
            return
        assets = {'/': 'index.html', '/index.html': 'index.html',
                  '/app.js': 'app.js', '/style.css': 'style.css'}
        if path in assets:
            f = STATIC / assets[path]
            self.body(f.read_bytes(), mimetypes.guess_type(str(f))[0] or 'application/octet-stream', head_only,
                      cache='no-cache')
        else:
            self.fail(404, 'Not found', head_only)

    def video(self, path: Path, head_only: bool):
        size = path.stat().st_size
        raw = self.headers.get('Range')
        if raw:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', raw.strip())
            if not match or not (match.group(1) or match.group(2)):
                self.range_invalid(size)
                return
            if match.group(1):
                start = int(match.group(1))
                end = min(size - 1, int(match.group(2))) if match.group(2) else size - 1
            else:
                length = int(match.group(2))
                start, end = max(0, size - length), size - 1
            if start >= size or start > end:
                self.range_invalid(size)
                return
            status = HTTPStatus.PARTIAL_CONTENT
        else:
            start, end, status = 0, size - 1, HTTPStatus.OK
        length = end - start + 1
        self.send_response(status)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(length))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        if status == HTTPStatus.PARTIAL_CONTENT:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        if head_only:
            return
        try:
            with path.open('rb') as file:
                file.seek(start)
                remaining = length
                while remaining:
                    chunk = file.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Browser cancels old range requests when switching qualities.

    def range_invalid(self, size):
        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
        self.send_header('Content-Range', f'bytes */{size}')
        self.send_header('Content-Length', '0')
        self.end_headers()


def main():
    ap = argparse.ArgumentParser(description='BBB bitrate switching lecture demo (stdlib only)')
    ap.add_argument('--root', type=Path, default=ROOT, help='adv_theme folder')
    ap.add_argument('--media-work', type=Path, default=None, help='adv_theme/runs/assets folder')
    ap.add_argument('--mpd', type=Path, default=None, help='BBB 2sec MPD')
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--check', action='store_true', help='Display representation availability and exit')
    ap.add_argument('--allow-unreceipted', action='store_true', help='Accept local test media without download receipts')
    args = ap.parse_args()
    root = args.root.resolve()
    work = (args.media_work or root / 'runs/assets').resolve()
    mpd = args.mpd or work / 'media/bbb/manifest.mpd'
    if not mpd.exists():
        mpd = root / 'configs/BigBuckBunny_2s_onDemand_2014_05_09.mpd' if args.mpd is None else mpd
    if not mpd.is_file():
        ap.error(f'MPD not found: {mpd}\nCheck --media-work or --mpd')
    catalog, lookup = build_catalog(root, work, mpd, require_receipt=not args.allow_unreceipted)
    if args.check:
        print(f'MPD: {mpd}\nMedia root: {catalog["mediaRoot"]}\nAvailable: {len(lookup)}/{len(catalog["representations"])}')
        for r in catalog['representations']:
            print(f'{r["index"]:02} {r["status"]:17} '
                  f'{r["kbps"]:>9.3f} kbps  {r["width"]}x{r["height"]}  rep_{r["index"]:02d}.mp4')
        return 0
    if not lookup:
        ap.error('No complete BBB rep_XX.mp4 files with valid receipts found. Download BBB media first; run --check.')
    print('BBB interactive demonstration')
    print('Media:', catalog['mediaRoot'], f'({len(lookup)}/{len(catalog["representations"])} files)')
    print(f'Open http://{args.host}:{args.port}  (for remote servers use SSH port forwarding)')
    print('Ctrl+C to stop. Budget slider simulates a selection policy; it does NOT throttle traffic.')
    server = DemoServer((args.host, args.port), catalog, lookup)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        print('\nStopped')
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
