"""End-to-end synthetic AVC/SIDX/XZ/cache/patch/split test; no real quality claim."""
import argparse
import functools
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import json
import lzma
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import threading
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.common import write_json, sha256
from dash_cnn.data.download import download, head
from dash_cnn.data.media import run
from dash_cnn.data.mpd import parse_sidx
from dash_cnn.data.prepare import prepare

def sidx_range(path):
    data = path.read_bytes(); pos = 0
    while pos + 8 <= len(data):
        size, kind = struct.unpack_from('>I4s', data, pos)
        if kind == b'sidx': return pos, pos + size - 1
        if size == 1: size = struct.unpack_from('>Q', data, pos + 8)[0]
        if not size: break
        pos += size
    raise ValueError('test encoder did not emit global SIDX')

class RangeHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        path = Path(self.translate_path(self.path)); length = path.stat().st_size
        start = int(self.headers.get('Range', 'bytes=0-').split('=')[1].split('-')[0])
        self.send_response(206 if 'Range' in self.headers else 200)
        self.send_header('Content-Length', str(length - start))
        if 'Range' in self.headers: self.send_header('Content-Range', f'bytes {start}-{length-1}/{length}')
        self.end_headers()
        with path.open('rb') as f:
            f.seek(start); self.wfile.write(f.read())

def main():
    a = argparse.ArgumentParser(); a.add_argument('--out', required=True); args = a.parse_args()
    report_out = Path(args.out)
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); work = root / 'work'; work.mkdir()
        # Also exercise interrupted-transfer resume and receipt reuse over real local HTTP.
        (root / 'bytes.bin').write_bytes(bytes(range(256)) * 100)
        server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(RangeHandler, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            url = f'http://127.0.0.1:{server.server_port}/bytes.bin'; dest = root / 'download.bin'
            dest.with_suffix('.bin.part').write_bytes((root / 'bytes.bin').read_bytes()[:500])
            write_json(dest.with_suffix('.bin.part.json'), head(url))
            download(url, dest); download(url, dest)
            assert dest.read_bytes() == (root / 'bytes.bin').read_bytes()
        finally:
            server.shutdown(); server.server_close(); thread.join()
        videos = []
        for number, vid in enumerate(('mini_bbb', 'mini_ed')):
            d = root / vid; d.mkdir(); raw = d / 'reference.y4m'; compressed = d / 'reference.y4m.xz'
            h, w, fps, frames = 64, 64, 4, 840
            yy, xx = np.indices((h, w)); rng = np.random.default_rng(2026 + number)
            texture = rng.normal(0, 18, (h, w))
            with raw.open('wb') as f:
                f.write(f'YUV4MPEG2 W{w} H{h} F{fps}:1 Ip A1:1 C420jpeg\n'.encode())
                for n in range(frames):
                    y = np.clip(128 + 45 * np.sin(xx * .21 + n * .17) + 30 * np.cos(yy * .19 - n * .13) + texture, 16, 235).astype(np.uint8)
                    f.write(b'FRAME\n' + y.tobytes() + bytes([128]) * (w * h // 2))
            with raw.open('rb') as src, lzma.open(compressed, 'wb') as dst:
                for b in iter(lambda: src.read(1024 * 1024), b''): dst.write(b)
            reps = []
            for i, crf in enumerate((8, 28, 46)):
                dst = d / f'rep_{i}.mp4'
                run(['ffmpeg', '-v', 'error', '-y', '-i', str(raw), '-an', '-c:v', 'libx264', '-preset', 'fast',
                     '-crf', str(crf), '-g', '8', '-keyint_min', '8', '-sc_threshold', '0', '-bf', '0',
                     '-movflags', '+dash+global_sidx', '-frag_duration', '2000000', str(dst)])
                begin, end = sidx_range(dst)
                reps.append(dict(index=i, id=f'mini_{i}', width=w, height=h, bandwidth=int(dst.stat().st_size * 8 / 210), fps=float(fps),
                                 url='synthetic://generated', index_start=begin, index_end=end, path=str(dst)))
            videos.append(dict(id=vid, reference_path=str(compressed), representations=reps))
        write_json(work / 'media_manifest.json', dict(status='DOWNLOADED', videos=videos))
        cfg = json.loads((ROOT / 'configs/avc4.json').read_text())
        cfg['segment_stride'] = 3; cfg['alignment']['minimum_median_correlation'] = .97
        report = prepare(cfg, root / 'experiment', media_work=work)
        assert report['split_audit']['segment_groups_disjoint']
        report.update(status='PASS', scope='synthetic AVC video pipeline only', generated_videos=2, generated_avc_encodes=6,
                      resumable_http_download=True, real_content_accuracy='NOT_MEASURED')
        write_json(report_out, report); print('PASS synthetic AVC video pipeline')

if __name__ == '__main__': main()
