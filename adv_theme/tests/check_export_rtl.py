"""Exported trained four-class model: exact logits checked on four validation patches plus reset replay."""
import argparse
import json
import sys
import tempfile
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.integer.model import load, infer, export
from dash_cnn.common import sha256, write_json
from run_rtl import simulate

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--weights', required=True); ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True); ap.add_argument('--iverilog', default='iverilog'); ap.add_argument('--vvp', default='vvp'); ap.add_argument('--ivl-base')
    a = ap.parse_args(); w = Path(a.weights); m = json.loads((w / 'manifest.json').read_text())
    if m['variant'] != 'final' or m['classes'] != 4 or m['codec_banks'] != 1:
        raise ValueError('AVC4 final single-bank RTL contract required')
    p = load(w / 'weights_int.npz'); d = load(a.data)
    if len(d['x']) < 4: raise ValueError('four validation patches required')
    indices = np.linspace(0, len(d['x']) - 1, 4, dtype=int)
    with tempfile.TemporaryDirectory() as td:
        t = Path(td); export(p, t)
        for i, j in enumerate(indices):
            x = d['x'][j]; z = infer(x, p)
            (t / f'input_{i}.mem').write_text(''.join(f'{int(v):02x}\n' for v in x.ravel()))
            (t / f'expected_{i}.mem').write_text(''.join(f'{int(v) & 0xffffffff:08x}\n' for v in z['scores']))
        result = simulate(t, a.out, iverilog=a.iverilog, vvp=a.vvp, ivl_base=a.ivl_base, engine=False)
    result.update(weights_sha256=sha256(w / 'weights_int.npz'), data_sha256=sha256(a.data), sample_indices=indices.tolist(),
                  weight_provenance=m.get('provenance'))
    write_json(a.out, result)

if __name__ == '__main__': main()
