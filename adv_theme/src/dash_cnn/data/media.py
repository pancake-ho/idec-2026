"""Luma-only caches. XZ reference is streamed, never expanded to a full raw file."""
import json
import lzma
import re
import shutil
import subprocess
from fractions import Fraction
from functools import lru_cache
from pathlib import Path
import numpy as np
from PIL import Image
from ..common import write_json, sha256

def run(args):
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError('Command failed: ' + repr(args) + '\n' + p.stderr[-8000:])
    return p.stdout

@lru_cache(maxsize=8)
def _ffmpeg_info(executable):
    """Inspect the installed binary, rather than guessing from a version number."""
    version = run([executable, '-version']).splitlines()[0]
    help_result = subprocess.run([executable, '-hide_banner', '-h', 'full'],
                                 capture_output=True, text=True, timeout=30)
    if help_result.returncode:
        raise RuntimeError('Cannot inspect FFmpeg options: ' + help_result.stderr[-2000:])
    help_text = help_result.stdout + '\n' + help_result.stderr
    if re.search(r'(?m)^\s*-fps_mode(?=\s|:)', help_text):
        sync = ('-fps_mode', 'passthrough')
    elif re.search(r'(?m)^\s*-vsync(?=\s|:)', help_text):
        sync = ('-vsync', '0')
    else:
        raise RuntimeError('FFmpeg supports neither -fps_mode nor -vsync. '
                           'Passthrough frame extraction is required; check ffmpeg -h full.')
    return executable, version, sync

def ffmpeg_info():
    executable = shutil.which('ffmpeg')
    if executable is None:
        raise FileNotFoundError('ffmpeg is not on PATH')
    executable, version, sync = _ffmpeg_info(executable)
    return dict(path=executable, version=version, frame_sync_args=list(sync))

def probe(path):
    data = json.loads(run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_streams', '-of', 'json', str(path)]))
    if not data['streams']:
        raise ValueError('no video stream')
    s = data['streams'][0]
    if s['codec_name'] != 'h264':
        raise ValueError('AVC/H.264 only')
    fps = float(Fraction(s['avg_frame_rate']))
    if abs(fps - float(Fraction(s['r_frame_rate']))) > 1e-6:
        raise ValueError('variable frame rate unsupported; frame-index alignment would be unsafe')
    if abs(float(s.get('start_time', 0))) > 1e-3:
        raise ValueError('nonzero stream start_time; explicitly normalize alignment before using this package')
    return dict(width=int(s['width']), height=int(s['height']), fps=fps,
                duration=float(s['duration']), frames=int(s.get('nb_frames', 0)),
                color_range=s.get('color_range', 'unspecified'), pix_fmt=s.get('pix_fmt'),
                sample_aspect_ratio=s.get('sample_aspect_ratio', '1:1'))

def _read_exact(f, n):
    parts = []; remaining = n
    while remaining:
        a = f.read(remaining)
        if not a:
            raise EOFError('truncated Y4M frame payload')
        parts.append(a); remaining -= len(a)
    return b''.join(parts)

def _skip(f, n):
    while n:
        size = min(n, 1024 * 1024); _read_exact(f, size); n -= size

def reference_cache(path, indices, out):
    indices = sorted(set(map(int, indices)))
    if not indices or indices[0] < 0:
        raise ValueError('nonnegative reference indices required')
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    manifest = out / 'cache.json'; identity = sha256(path)
    if manifest.exists():
        previous = json.loads(manifest.read_text())
        if previous['source_sha256'] != identity:
            raise ValueError('reference cache source changed; use a new run directory')
        if all((out / f'{i:08d}.png').exists() for i in indices):
            return previous
    opener = lzma.open if str(path).endswith('.xz') else open
    with opener(path, 'rb') as f:
        header = f.readline(4096)
        if not header.startswith(b'YUV4MPEG2 ') or not header.endswith(b'\n'):
            raise ValueError('Y4M reference header required')
        fields = header.decode().strip().split()[1:]; d = {s[0]: s[1:] for s in fields}
        w, h = int(d['W']), int(d['H']); fps = float(Fraction(d['F'].replace(':', '/')))
        chroma = d.get('C', '420jpeg')
        if w % 2 or h % 2 or chroma not in ('420', '420jpeg', '420mpeg2', '420paldv'):
            raise ValueError('8bit planar YUV420, even dimensions required')
        wanted = set(indices); size_y = w * h; current = 0
        while current <= indices[-1]:
            marker = f.readline(4096)
            if not marker.startswith(b'FRAME') or not marker.endswith(b'\n'):
                raise EOFError(f'reference ends before frame {current} or has an invalid marker')
            if current in wanted:
                y = np.frombuffer(_read_exact(f, size_y), np.uint8).reshape(h, w)
                Image.fromarray(y).save(out / f'{current:08d}.png')
                _skip(f, size_y // 2)
            else:
                _skip(f, size_y * 3 // 2)
            current += 1
            if current % 1000 == 0:
                print('reference stream frame', current, flush=True)
    result = dict(width=w, height=h, fps=fps, source_sha256=identity, header=header.decode().strip(),
                  cached_indices=indices, source_range='preserved Y code; no automatic range remapping')
    write_json(manifest, result); return result

def decoded_cache(path, indices, out):
    info = ffmpeg_info()
    indices = sorted(set(map(int, indices))); out = Path(out); out.mkdir(parents=True, exist_ok=True)
    manifest = out / 'cache.json'; identity = sha256(path)
    if manifest.exists():
        old = json.loads(manifest.read_text())
        if old['source_sha256'] != identity:
            raise ValueError('decoded cache source changed; use a new run directory')
        if old['indices'] == indices and all((out / f'{i:08d}.png').exists() for i in indices):
            return
    expression = '+'.join(f'eq(n,{i})' for i in indices)
    # Only these temporary names belong to this decoder invocation. Remove leftovers
    # from an interrupted extraction before using FFmpeg's numbered image output.
    for temporary in out.glob('selected_*.png'):
        temporary.unlink()
    # Direct subprocess argument: no shell interpretation of the filter string.
    run([info['path'], '-v', 'error', '-y', '-i', str(path), '-vf', f"select='{expression}',extractplanes=y",
         *info['frame_sync_args'], '-pix_fmt', 'gray', '-start_number', '0', str(out / 'selected_%08d.png')])
    files = sorted(out.glob('selected_*.png'))
    if len(files) != len(indices):
        raise ValueError(f'decoded selected frame count {len(files)} != {len(indices)}')
    for p, i in zip(files, indices):
        p.replace(out / f'{i:08d}.png')
    write_json(manifest, dict(source_sha256=identity, indices=indices,
                             ffmpeg_version=info['version'], frame_sync_args=info['frame_sync_args']))

def read_y(path):
    with Image.open(path) as im:
        if im.mode != 'L':
            raise ValueError('8-bit grayscale cache required')
        return np.asarray(im).copy()

def reference_at(path, width, height):
    with Image.open(path) as im:
        return np.asarray(im.resize((width, height), Image.Resampling.BICUBIC)).copy()
