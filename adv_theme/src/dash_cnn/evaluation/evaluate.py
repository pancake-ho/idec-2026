"""Evaluate frozen integer weights; test never selects model or changes label boundaries."""
from pathlib import Path
import numpy as np
from ..data.audit import load, validate_splits
from ..integer.model import load as load_weights, infer
from ..common import write_json, sha256
from .metrics import metrics

def evaluate(work, variant='final'):
    work = Path(work); datasets = [load(work / 'data' / (s + '.npz')) for s in ('train', 'validation', 'test')]
    audit = validate_splits(*datasets); d = datasets[-1]
    pth = work / 'models' / variant / 'integer' / 'weights_int.npz'; p = load_weights(pth)
    pred = np.array([infer(x, p, variant=variant)['decision'] for x in d['x']])
    synthetic = any(bool(np.asarray(a.get('synthetic_smoke', False)).item()) for a in datasets)
    report = dict(status='SYNTHETIC_SMOKE_ONLY' if synthetic else 'TEST_EVALUATED', test=metrics(d['y'], pred, d['video_id']), split_audit=audit,
                  weights_sha256=sha256(pth), test_sha256=sha256(work / 'data/test.npz'), ppa='NOT_MEASURED')
    write_json(work / 'reports' / (variant + '_test.json'), report)
    np.savez_compressed(work / 'reports' / (variant + '_test_predictions.npz'), sample_id=d['sample_id'], y=d['y'], pred=pred)
    print(report['test']); return report
