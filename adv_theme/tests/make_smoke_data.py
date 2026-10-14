"""Synthetic four-bin data tests plumbing only; never a real-video quality result."""
import argparse
from pathlib import Path
import sys
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.data.labels import ssim_local, grade
from dash_cnn.data.patches import controls
from dash_cnn.data.audit import validate_splits
from dash_cnn.common import write_json

def dataset(split, start, count=6):
    rng = np.random.default_rng(2026 + start); records = []
    for target in range(4):
        for j in range(count):
            ref = np.clip(rng.normal(128, 30, (28, 28)), 0, 255).astype(np.uint8)
            chosen = None
            for sigma in (0, 2, 4, 6, 8, 10, 12, 15, 18, 22, 28, 40, 60, 90):
                q = np.clip(ref.astype(float) + rng.normal(0, sigma, (28, 28)), 0, 255).astype(np.uint8)
                s = ssim_local(ref, q)
                if grade(s) == target:
                    chosen = q, s; break
            if chosen is None: raise AssertionError('cannot construct smoke bin')
            q, s = chosen; n = len(records); t = start + n * 2.; md, hc = controls(q, 100000, 64, 64, 4)
            records.append(dict(x=q, y=target, ssim=s, video_id='synthetic', group_id=f'{split}/{n}', sample_id=f'{split}/{n}',
                                source_sha256='synthetic-only-2026', segment_start=t, segment_duration=2., guard_seconds=2.,
                                frame_index=int(t * 4), metadata=md, handcrafted=hc))
    d = {k: np.asarray([r[k] for r in records]) for k in records[0]}; d['synthetic_smoke'] = np.array(True)
    return d

def main():
    p = argparse.ArgumentParser(); p.add_argument('--out', required=True); a = p.parse_args(); out = Path(a.out)
    out.joinpath('data').mkdir(parents=True, exist_ok=True)
    if any((out / 'data' / (s + '.npz')).exists() for s in ('train', 'validation', 'test')):
        raise ValueError('work data already exists; use a new smoke directory')
    ds = [dataset(s, t) for s, t in zip(('train', 'validation', 'test'), (0, 100, 200))]
    audit = validate_splits(*ds)
    for s, d in zip(('train', 'validation', 'test'), ds): np.savez_compressed(out / 'data' / (s + '.npz'), **d)
    write_json(out / 'reports/synthetic_data.json', dict(status='SYNTHETIC_SMOKE_ONLY', split_audit=audit))
    print('SYNTHETIC_SMOKE_ONLY', out)

if __name__ == '__main__': main()
