"""Meaningful arithmetic, class-boundary, export and four-output network checks."""
import argparse
import copy
import json
import sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT / 'src'))
from dash_cnn.integer.arithmetic import conv_direct
from dash_cnn.integer.model import validate, infer, effective, dwm_tile, rne_shift, export, load
from dash_cnn.data.labels import grade, ssim_local
from dash_cnn.spec import counts
from dash_cnn.common import write_json

def fixture(seed=2026):
    rng = np.random.default_rng(seed)
    def w(shape):
        a = rng.integers(-32, 32, shape, dtype=np.int64)
        a[..., :3, :3] = rng.integers(-128, 128, a[..., :3, :3].shape); a[..., 3:, 3:] = 0
        return a
    return dict(q1=w((6, 1, 5, 5)), q2=w((12, 6, 5, 5)), qfc=rng.integers(-32, 32, (4, 192), dtype=np.int64),
                b1=rng.integers(-100, 100, 6, dtype=np.int64), b2=rng.integers(-100, 100, 12, dtype=np.int64),
                bfc=rng.integers(-100, 100, 4, dtype=np.int64), s1=np.array(8), s2=np.array(9))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--out', default=str(ROOT / 'runs/selftest')); a = ap.parse_args()
    out = Path(a.out); dst = out / 'fixtures'; rng = np.random.default_rng(2026); p = fixture(); validate(p)
    rounds = 0
    for s in range(32):
        values = list(range(-4096, 4097)) + [-2**31, 2**31 - 1]
        if s: values += [2**(s - 1), -2**(s - 1), 3 * 2**(s - 1), -3 * 2**(s - 1)]
        x = np.asarray(values, np.int64)
        # Exact Python integer ties-to-even oracle (no float precision assumptions).
        def oracle(v):
            q, r = divmod(int(v), 1 << s)
            return q + int(r * 2 > (1 << s) or (r * 2 == (1 << s) and q % 2 == 1))
        assert np.array_equal(rne_shift(x, s), np.array([oracle(v) for v in values])); rounds += len(values)
    for j in range(1000):
        x = rng.integers(0, 256, (6, 6)); q = p['q2'][j % 12, j % 6]
        if j < 4: x.fill(255 if j % 2 else 0)
        assert np.array_equal(dwm_tile(x, q), conv_direct(x[None], effective(q)[None, None])[0])
    images = [np.zeros((28, 28), np.uint8), np.full((28, 28), 255, np.uint8),
              rng.integers(0, 256, (28, 28), dtype=np.uint8), ((np.indices((28, 28)).sum(0) % 2) * 255).astype(np.uint8)]
    for x in images:
        for profile in (0, 1):
            d = infer(x, p, profile); w = infer(x, p, profile, 'dwm')
            for key in d: assert np.array_equal(d[key], w[key])
            assert len(d['scores']) == 4
    assert [grade(x) for x in (.95, .949, .90, .899, .8000001, .8, -1)] == [0, 1, 1, 2, 2, 3, 3]
    assert abs(ssim_local(images[2], images[2]) - 1) < 1e-12
    for key, value in [('qfc', p['qfc'][:3]), ('bfc', np.array([2**31, 0, 0, 0]))]:
        bad = copy.deepcopy(p); bad[key] = value
        try: validate(bad)
        except (ValueError, OverflowError): pass
        else: raise AssertionError('invalid export accepted')
    bad = copy.deepcopy(p); bad['q1'][0, 0, 4, 4] = 1
    try: validate(bad)
    except ValueError: pass
    else: raise AssertionError('mask violation accepted')
    export(p, dst)
    for key in p: assert np.array_equal(p[key], load(dst / 'weights_int.npz')[key])
    m = json.loads((dst / 'manifest.json').read_text()); m['provenance'] = 'SYNTHETIC_SMOKE_ONLY'; write_json(dst / 'manifest.json', m)
    for i, x in enumerate(images):
        (dst / f'input_{i}.mem').write_text(''.join(f'{int(v):02x}\n' for v in x.ravel()))
        scores = infer(x, p)['scores']
        (dst / f'expected_{i}.mem').write_text(''.join(f'{int(v) & 0xffffffff:08x}\n' for v in scores))
    report = dict(status='PASS', random_tiles=1000, full_networks=8, rounding_values=rounds,
                  classes=4, exact_boundaries=True, overflow_and_mask_rejection=True, counts=counts(),
                  real_video_accuracy='NOT_MEASURED', ppa='NOT_MEASURED')
    write_json(out / 'python_validation.json', report); print(json.dumps(report))

if __name__ == '__main__': main()
