"""Shared I/O; existing analyze/ reference sources and all RTL remain untouched."""
from __future__ import annotations
import csv
import hashlib
import json
import sys
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
REPO = PACKAGE.parents[1]
sys.path.insert(0, str(PACKAGE.parent))
from io_utils import load_parameters, load_input_1000  # noqa: E402
from rtl_model import RTLReferenceCNN, RTLTrace  # noqa: E402
from fixed_point import wrap_signed, part_select_signed, required_signed_bits  # noqa: E402

COMMIT = "229c22ed888a404cdf2da544fdade00b35748c0f"
DATA_BLOB = "297731cdb5dd28abceed33043856b1186fa85b9a"
SOURCES = {
    "verilog/pfdw_pipe49_booth_engine_v18a.sv": "59d43ee41f5ad6d1b1c5ee6b4fd2f05afe63b7c6",
    "verilog/chip_pfdw_fc_v18a.sv": "fe31b559be9cfd05e11096e80008b363481c2ca2",
    "verilog/chip_v18a_top.v": "19b05bbbd0d2cfb101f9a65af109607df979f819",
    "analyze/rtl_model.py": "0511fe6266a18c640f729d50cd2cdee4816276b2",
    "analyze/fixed_point.py": "2f48c1a35e395a299ae795f5f757af25f6e5473f",
    "analyze/config.py": "ffba3623c9ede3f32015e9fa33221c231709f42c",
    "analyze/io_utils.py": "f4f65ee5bc8a76f8a0b996d6a22ac607e0901531",
}

def git_blob(path):
    b = Path(path).read_bytes()
    return hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest()

def source_manifest(repo):
    rows = []
    for rel, expected in SOURCES.items():
        p = Path(repo) / rel
        actual = git_blob(p) if p.is_file() else None
        rows.append(dict(path=rel, expected_blob=expected, actual_blob=actual,
                         matches=actual == expected))
    if not all(r["matches"] for r in rows):
        bad = [r["path"] for r in rows if not r["matches"]]
        raise ValueError("V18A source snapshot differs or is missing: " + ", ".join(bad))
    return rows

def json_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                    encoding="utf-8")

def csv_write(path, rows, fields=None):
    rows = list(rows)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or (list(rows[0]) if rows else [])
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

def dataset_audit(dataset, labels_path=None, seed=2026):
    images = load_input_1000(dataset)
    if labels_path is None:
        if git_blob(dataset) != DATA_BLOB:
            raise ValueError("Unknown dataset: supply --labels with one decimal label per image. "
                             "The index%10 convention is only automatic for the verified organizer file.")
        labels = np.arange(len(images), dtype=np.int64) % 10
        label_source = "verified organizer index%10 convention"
    else:
        labels = np.loadtxt(labels_path, dtype=np.int64).reshape(-1)
        if len(labels) != len(images) or np.any((labels < 0) | (labels > 9)):
            raise ValueError("Labels must contain exactly one integer in 0..9 per image.")
        label_source = str(Path(labels_path).resolve())
    groups = {}
    for i, image in enumerate(images):
        key = hashlib.sha256(image.astype(np.uint8).tobytes()).hexdigest()
        groups.setdefault(key, []).append(i)
    unique_ids = np.array([ids[0] for ids in groups.values()], dtype=np.int64)
    membership = []
    rng = np.random.default_rng(seed)
    split = {k: [] for k in ("calibration", "validation", "holdout")}
    unique_split = {}
    for label in range(10):
        ids = unique_ids[labels[unique_ids] == label].copy()
        if len(ids) < 5:
            raise ValueError(f"Need >=5 unique samples per class for a 60/20/20 split; class {label} has {len(ids)}.")
        rng.shuffle(ids)
        ncal = int(len(ids) * 0.6)
        nval = int(len(ids) * 0.2)
        for key, part in zip(split, (ids[:ncal], ids[ncal:ncal+nval], ids[ncal+nval:])):
            split[key].extend(map(int, part))
            unique_split.update({int(i): key for i in part})
    for key, ids in groups.items():
        if len(set(map(int, labels[ids]))) != 1:
            raise ValueError("Identical pixels have conflicting labels: " + str(ids))
        for i in ids:
            membership.append(dict(image_index=i, representative=ids[0], label=int(labels[i]),
                                   image_sha256=key, split=unique_split[ids[0]], multiplicity=len(ids)))
    for key in split:
        split[key] = np.array(sorted(split[key]), dtype=np.int64)
    counts = [len(ids) for ids in groups.values()]
    audit = dict(dataset=str(Path(dataset).resolve()), dataset_blob=git_blob(dataset),
                 dataset_sha256=hashlib.sha256(Path(dataset).read_bytes()).hexdigest(),
                 image_count=len(images), unique_image_count=len(unique_ids), label_source=label_source,
                 multiplicity_histogram={str(n): counts.count(n) for n in sorted(set(counts))},
                 unique_per_class={str(c): int(np.sum(labels[unique_ids] == c)) for c in range(10)},
                 seed=seed, split_sizes={k: len(v) for k, v in split.items()},
                 caveat="All splits come from the supplied file. Only 100 unique images in the default data; "
                        "this is exploratory evidence, not an independent MNIST benchmark.")
    return images, labels, unique_ids, split, audit, sorted(membership, key=lambda r: r["image_index"])

def run_records(model, images, ids):
    preds, traces = [], []
    for i in ids:
        p, t = model.forward(images[int(i)], return_trace=True)
        preds.append(p)
        traces.append(t)
    return np.array(preds, dtype=np.int64), traces

def trace_arrays(traces):
    names = ("conv1_acc_math", "conv1_out", "pool1", "conv2_partial_math", "conv2_acc20",
             "conv2_out", "pool2", "fc_acc20", "logits")
    return {name: np.stack([getattr(t, name) for t in traces]) for name in names}
