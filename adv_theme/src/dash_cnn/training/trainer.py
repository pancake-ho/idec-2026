"""FP32 -> train-only calibration -> QAT -> deployment-integer validation -> export."""
import copy
import csv
import json
from pathlib import Path
import random
import numpy as np
import torch
from torch.nn import functional as F
from ..spec import NUM_CLASSES
from ..models.cnn import DASHCNN
from ..data.audit import load, validate_splits
from ..integer.model import infer, export
from ..evaluation.metrics import metrics
from ..common import write_json, sha256

@torch.no_grad()
def evaluate_torch(model, d):
    model.eval(); pred = []
    device, dtype = next(model.parameters()).device, next(model.parameters()).dtype
    for i in range(0, len(d['x']), 128):
        x = torch.from_numpy(d['x'][i:i + 128])[:, None].to(device, dtype) / 256
        pred.extend(model(x).argmax(1).cpu().numpy())
    return metrics(d['y'], np.asarray(pred), d['video_id'])

def evaluate_integer(model, d):
    p = model.export_integer()
    pred = np.array([infer(x, p, variant=model.variant)['decision'] for x in d['x']])
    return metrics(d['y'], pred, d['video_id'])

def fit(model, td, vd, *, epochs, lr, batch_size, seed, quantized):
    if epochs < 1 or batch_size < 1 or lr <= 0:
        raise ValueError('positive epochs/batch/lr')
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    rng = np.random.default_rng(seed)
    counts = np.bincount(td['y'], minlength=NUM_CLASSES)
    if np.any(counts == 0):
        raise ValueError('train needs all four SSIM classes; inspect dataset_audit.json, keep thresholds fixed')
    probs = 1. / counts[td['y']]; probs /= probs.sum()
    device = next(model.parameters()).device; best = -1.; state = None; history = []
    for epoch in range(epochs):
        ix = rng.choice(len(td['x']), len(td['x']), replace=True, p=probs)
        model.train(); total_loss = 0.; total = 0
        for i in range(0, len(ix), batch_size):
            ids = ix[i:i + batch_size]
            x = torch.from_numpy(td['x'][ids])[:, None].to(device).float() / 256
            y = torch.from_numpy(td['y'][ids]).to(device).long()
            opt.zero_grad(); loss = F.cross_entropy(model(x), y); loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.)
            opt.step(); total_loss += float(loss.detach()) * len(ids); total += len(ids)
        m = evaluate_integer(model, vd) if quantized else evaluate_torch(model, vd)
        score = m['macro_f1']
        row = dict(stage='qat' if quantized else 'fp32', epoch=epoch + 1, loss=total_loss / total,
                   validation_accuracy=m['accuracy'], validation_macro_f1=score,
                   validation_metrics=m, selection_arithmetic='integer' if quantized else 'float32')
        history.append(row); print(row['stage'], epoch + 1, 'loss', round(row['loss'], 5), 'val_F1', round(score, 5), flush=True)
        if score > best:
            best = score; state = copy.deepcopy(model.state_dict())
    model.load_state_dict(state); return history

@torch.no_grad()
def audit_export(model, data, params):
    m = copy.deepcopy(model).cpu().double().eval(); q = m.quant; n = 0
    for i in np.linspace(0, len(data['x']) - 1, min(6, len(data['x'])), dtype=int):
        x = data['x'][i]; ref = infer(x, params, variant=m.variant); win = infer(x, params, method='dwm', variant=m.variant)
        scores, p1, p2 = m(torch.tensor(x, dtype=torch.float64)[None, None] / 256, maps=True)
        for key, tensor, exp in [('pool1', p1, q['ea1']), ('pool2', p2, q['ea2']), ('scores', scores, q['ea2'] + q['ewfc'])]:
            got = np.rint(tensor[0].numpy() / 2. ** exp).astype(np.int64)
            if not np.array_equal(ref[key], win[key]) or not np.array_equal(got, ref[key]):
                raise AssertionError('QAT/NumPy/direct/PFDW export mismatch: ' + key)
        n += 1
    return n

def train(cfg, work, device='cpu', base_epochs=None, qat_epochs=None, variant=None):
    work = Path(work); c = dict(cfg['training'])
    if base_epochs is not None: c['base_epochs'] = base_epochs
    if qat_epochs is not None: c['qat_epochs'] = qat_epochs
    if variant is not None: c['variant'] = variant
    td, vd = [load(work / 'data' / (s + '.npz')) for s in ('train', 'validation')]
    audit = validate_splits(td, vd)
    if not all(np.bincount(td['y'], minlength=NUM_CLASSES)):
        raise ValueError('train needs all four classes; inspect dataset_audit.json before training')
    if not all(np.bincount(vd['y'], minlength=NUM_CLASSES)):
        raise ValueError('validation needs all four classes for model selection')
    seed = int(c['seed']); random.seed(seed); np.random.seed(seed); torch.manual_seed(seed)
    torch.set_num_threads(2)
    if device.startswith('cuda') and not torch.cuda.is_available():
        raise ValueError('CUDA requested but unavailable; use --device cpu')
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed); torch.backends.cudnn.benchmark = False; torch.backends.cudnn.deterministic = True
    out = work / 'models' / c['variant']
    if out.exists():
        raise ValueError('model output already exists; use a new work directory or a different variant')
    out.mkdir(parents=True)
    model = DASHCNN(c['variant']).to(device); model.train_base()
    hist = fit(model, td, vd, epochs=c['base_epochs'], lr=c['base_lr'], batch_size=c['batch_size'], seed=seed, quantized=False)
    torch.save(dict(state=model.cpu().state_dict(), variant=model.variant), out / 'fp32.pt'); model.to(device)
    idx = np.random.default_rng(seed).choice(len(td['x']), min(c['calibration_samples'], len(td['x'])), replace=False)
    # Bound calibration memory on GPU; no validation/test samples are used.
    model.calibrate(torch.from_numpy(td['x'][idx])[:, None].to(device).float() / 256)
    hist += fit(model, td, vd, epochs=c['qat_epochs'], lr=c['qat_lr'], batch_size=c['batch_size'], seed=seed + 1, quantized=True)
    params = model.export_integer(); crosschecks = audit_export(model, vd, params)
    export(params, out / 'integer', model.variant)
    synthetic = bool(np.asarray(td.get('synthetic_smoke', False)).item()) or bool(np.asarray(vd.get('synthetic_smoke', False)).item())
    status = 'SYNTHETIC_SMOKE_ONLY' if synthetic else 'TRAINED_CANDIDATE_TEST_AND_PPA_PENDING'
    manifest = json.loads((out / 'integer' / 'manifest.json').read_text())
    manifest.update(provenance=status, seed=seed, train_sha256=sha256(work / 'data/train.npz'),
                    validation_sha256=sha256(work / 'data/validation.npz'), quant=model.quant)
    write_json(out / 'integer' / 'manifest.json', manifest)
    torch.save(dict(state=model.cpu().state_dict(), quant=model.quant, variant=model.variant, classes=NUM_CLASSES), out / 'qat.pt')
    with (out / 'history.csv').open('w', newline='') as f:
        keys = ('stage', 'epoch', 'loss', 'validation_accuracy', 'validation_macro_f1')
        w = csv.DictWriter(f, fieldnames=keys, extrasaction='ignore'); w.writeheader(); w.writerows(hist)
    report = dict(status=status, training_config=c, split_audit=audit, history=hist, integer_crosschecks=crosschecks,
                  final_validation=evaluate_integer(model, vd), quant=model.quant, torch_version=torch.__version__,
                  test='NOT_READ', ppa='NOT_MEASURED', codec_adaptation='NOT_USED_AVC_SHARED')
    write_json(out / 'training_report.json', report); print(status); return out
