"""Observable metadata and metadata+spatial linear controls, selected on validation only."""
import copy
from pathlib import Path
import numpy as np
import torch
from ..data.audit import load, validate_splits
from ..common import write_json
from ..spec import NUM_CLASSES
from .metrics import metrics

def baselines(work, epochs=300):
    work = Path(work); td, vd = [load(work / 'data' / (s + '.npz')) for s in ('train', 'validation')]
    validate_splits(td, vd); torch.manual_seed(2026); torch.set_num_threads(2)
    out = work / 'models' / 'controls'; out.mkdir(parents=True, exist_ok=True); result = {}
    for key in ('metadata', 'handcrafted'):
        mu = td[key].mean(0); sd = td[key].std(0); sd = np.where(sd > 1e-9, sd, 1.)
        x = torch.tensor((td[key] - mu) / sd, dtype=torch.float32); vx = torch.tensor((vd[key] - mu) / sd, dtype=torch.float32)
        y = torch.tensor(td['y']).long(); model = torch.nn.Linear(x.shape[1], NUM_CLASSES)
        opt = torch.optim.Adam(model.parameters(), lr=.03); best = -1.; chosen = None
        cw = torch.tensor(1 / np.maximum(np.bincount(td['y'], minlength=NUM_CLASSES), 1), dtype=torch.float32); cw /= cw.mean()
        for _ in range(epochs):
            opt.zero_grad(); loss = torch.nn.functional.cross_entropy(model(x), y, weight=cw); loss.backward(); opt.step()
            with torch.no_grad(): pred = model(vx).argmax(1).numpy()
            score = metrics(vd['y'], pred)['macro_f1']
            if score > best: best = score; chosen = copy.deepcopy(model.state_dict())
        model.load_state_dict(chosen)
        with torch.no_grad(): pred = model(vx).argmax(1).numpy()
        result[key] = metrics(vd['y'], pred, vd['video_id'])
        np.savez_compressed(out / (key + '.npz'), mu=mu, sd=sd, w=model.weight.detach().numpy(), b=model.bias.detach().numpy())
    write_json(out / 'validation.json', result); return result
