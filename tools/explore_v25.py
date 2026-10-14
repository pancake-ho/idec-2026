#!/usr/bin/env python3
"""
V25 PPA Searcher for the KNU/IDEC CNN accelerator project.

Purpose
-------
Search numerical/hardware candidates BEFORE writing another RTL version.
The model follows the V24 PFDW datapath at inference level:
  * 6x6 tile + 5x5 kernel -> four outputs through the same decomposed Winograd
    transforms used by pfdw_pipe49_booth_engine_v24.sv.
  * V24-style layer-wise weight LSB dropping with scale restoration.
  * Conv1/Conv2 fixed-point quantization, ReLU/max-pool, and FC score slicing.

It additionally explores V25 candidates:
  * layer-wise weight precision (W4..W8)
  * layer-wise activation precision for fmap1/fmap2 (8..11 bits)
  * unstructured pruning thresholds
  * structured Conv1/Conv2 channel pruning
  * transformed-domain signed-power coefficient coding for convolution
    (pot1 / csd2 / sp2) and signed-power coding for FC weights

IMPORTANT
---------
The reported PPA score is a ranking proxy, NOT an OpenROAD prediction.
Always synthesize the best few candidates. The accuracy/inference path is the
part intended to be bit-faithful to the V24 arithmetic conventions.

Typical usage (Windows PowerShell):
  python explore_v25.py --data-dir C:/cnn_verilog/test24 --num-images 200 --search
  python explore_v25.py --data-dir C:/cnn_verilog/test24 --num-images 1000 --validate

Typical usage (Linux):
  python3 explore_v25.py --data-dir ~/cnn_data --num-images 200 --search

Outputs are written under --out-dir (default: v25_search_out).
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import time
from dataclasses import asdict, dataclass, replace
from functools import lru_cache
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view


# -----------------------------------------------------------------------------
# Two's-complement helpers
# -----------------------------------------------------------------------------

def wrap_signed(x, bits: int):
    """Wrap scalar/ndarray to a signed two's-complement integer of width bits."""
    mod = 1 << bits
    half = 1 << (bits - 1)
    a = np.asarray(x, dtype=np.int64)
    u = np.bitwise_and(a, mod - 1)
    y = np.where(u >= half, u - mod, u).astype(np.int64)
    if np.ndim(x) == 0:
        return int(y)
    return y


def signed_slice(x, hi: int, lo: int):
    """Verilog-style signed slice x[hi:lo], interpreted as signed."""
    width = hi - lo + 1
    a = np.asarray(x, dtype=np.int64)
    u = np.bitwise_and(a, (1 << (hi + 1)) - 1)
    s = np.right_shift(u, lo)
    y = wrap_signed(s, width)
    if np.ndim(x) == 0:
        return int(y)
    return y


def popcount3(mask: int) -> int:
    return ((mask >> 0) & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1)


# -----------------------------------------------------------------------------
# Exact V24 PFDW transforms (integer form)
# -----------------------------------------------------------------------------

def _b3(x0, x1, x2, x3, o):
    return (x0 - x2, x1 + x2, -x1 + x2, x1 - x3)[o]


def _b2(x0, x1, x2, o):
    return (x0 - x1, x1, -x1 + x2)[o]


def _g3(x0, x1, x2, o):
    return (x0 << 1, x0 + x1 + x2, x0 - x1 + x2, x2 << 1)[o]


def _g2(x0, x1, o):
    return (x0, x0 + x1, x1)[o]


def _a3(x0, x1, x2, x3, o):
    return x0 + x1 + x2 if o == 0 else x1 - x2 - x3


def _a2(x0, x1, x2, o):
    return x0 + x1 if o == 0 else x1 + x2


def transform_tile_scalar(tile: Sequence[Sequence[int]]) -> List[int]:
    """V24 B transform: 6x6 activation tile -> 49 lanes."""
    p1 = [0] * 49
    # 3x3 block
    for r in range(4):
        for o in range(4):
            p1[r * 4 + o] = _b3(*tile[r][0:4], o)
    # 3x2 block
    for r in range(4):
        for o in range(3):
            p1[16 + r * 3 + o] = _b2(*tile[r][3:6], o)
    # 2x3 block
    for r in range(3):
        for o in range(4):
            p1[28 + r * 4 + o] = _b3(*tile[r + 3][0:4], o)
    # 2x2 block
    for r in range(3):
        for o in range(3):
            p1[40 + r * 3 + o] = _b2(*tile[r + 3][3:6], o)

    p2 = [0] * 49
    # block 0 4x4
    for j in range(4):
        for i in range(4):
            p2[i * 4 + j] = _b3(p1[0 * 4 + j], p1[1 * 4 + j],
                                 p1[2 * 4 + j], p1[3 * 4 + j], i)
    # block 1 4x3
    for j in range(3):
        for i in range(4):
            p2[16 + i * 3 + j] = _b3(p1[16 + 0 * 3 + j], p1[16 + 1 * 3 + j],
                                      p1[16 + 2 * 3 + j], p1[16 + 3 * 3 + j], i)
    # block 2 3x4
    for j in range(4):
        for i in range(3):
            p2[28 + i * 4 + j] = _b2(p1[28 + 0 * 4 + j], p1[28 + 1 * 4 + j],
                                      p1[28 + 2 * 4 + j], i)
    # block 3 3x3
    for j in range(3):
        for i in range(3):
            p2[40 + i * 3 + j] = _b2(p1[40 + 0 * 3 + j], p1[40 + 1 * 3 + j],
                                      p1[40 + 2 * 3 + j], i)
    return p2


def transform_kernel_scalar(k: Sequence[Sequence[int]]) -> List[int]:
    """V24 G transform: 5x5 spatial kernel -> 49 transformed coefficients."""
    p1 = [0] * 35
    for r in range(3):
        for o in range(4):
            p1[r * 4 + o] = _g3(*k[r][0:3], o)
    for r in range(3):
        for o in range(3):
            p1[12 + r * 3 + o] = _g2(*k[r][3:5], o)
    for r in range(2):
        for o in range(4):
            p1[21 + r * 4 + o] = _g3(*k[r + 3][0:3], o)
    for r in range(2):
        for o in range(3):
            p1[29 + r * 3 + o] = _g2(*k[r + 3][3:5], o)

    p2 = [0] * 49
    for j in range(4):
        for i in range(4):
            p2[i * 4 + j] = _g3(p1[0 * 4 + j], p1[1 * 4 + j], p1[2 * 4 + j], i)
    for j in range(3):
        for i in range(4):
            p2[16 + i * 3 + j] = _g3(p1[12 + 0 * 3 + j], p1[12 + 1 * 3 + j],
                                      p1[12 + 2 * 3 + j], i)
    for j in range(4):
        for i in range(3):
            p2[28 + i * 4 + j] = _g2(p1[21 + 0 * 4 + j], p1[21 + 1 * 4 + j], i)
    for j in range(3):
        for i in range(3):
            p2[40 + i * 3 + j] = _g2(p1[29 + 0 * 3 + j], p1[29 + 1 * 3 + j], i)
    return p2


def _build_linear_matrix(kind: str) -> np.ndarray:
    if kind == "B":
        mat = np.zeros((49, 36), dtype=np.int64)
        for n in range(36):
            x = [[0] * 6 for _ in range(6)]
            x[n // 6][n % 6] = 1
            mat[:, n] = np.asarray(transform_tile_scalar(x), dtype=np.int64)
        return mat
    if kind == "G":
        mat = np.zeros((49, 25), dtype=np.int64)
        for n in range(25):
            x = [[0] * 5 for _ in range(5)]
            x[n // 5][n % 5] = 1
            mat[:, n] = np.asarray(transform_kernel_scalar(x), dtype=np.int64)
        return mat
    raise ValueError(kind)


B_MAT = _build_linear_matrix("B")
G_MAT = _build_linear_matrix("G")

LANE_AW = np.array([
    14 if i == 5 else 12 if i in {17,23,26,32,34,35,41,43,44,45,47} else 13
    for i in range(49)
], dtype=np.int64)

_LANE_BW_BASE = []
for i in range(49):
    if i in {5,6,9,10}:
        v = 12
    elif i in {1,2,4,7,8,11,13,14,20,23,33,34}:
        v = 11
    elif i in {0,3,12,15,17,19,21,22,24,26,29,30,32,35,37,38,44}:
        v = 10
    elif i in {16,18,25,27,28,31,36,39,41,43,45,47}:
        v = 9
    else:
        v = 8
    _LANE_BW_BASE.append(v)
LANE_BW_BASE = np.asarray(_LANE_BW_BASE, dtype=np.int64)

LANE_PW_BASE = np.asarray([
    22,23,23,22, 23,25,24,23, 23,24,24,23, 22,23,23,22,
    21,21,21,22, 23,22,22,22, 22,21,21,21,
    21,22,22,21, 21,23,22,21, 21,22,22,21,
    20,20,20,20, 21,20,20,20, 20
], dtype=np.int64)


def inverse_pfdw(p3: np.ndarray) -> np.ndarray:
    """V24 P4/P5/P6 inverse transform, vectorized over leading dimensions."""
    p = np.asarray(p3, dtype=np.int64)
    lead = p.shape[:-1]
    h33 = np.zeros(lead + (4, 2), dtype=np.int64)
    h32 = np.zeros(lead + (4, 2), dtype=np.int64)
    h23 = np.zeros(lead + (3, 2), dtype=np.int64)
    h22 = np.zeros(lead + (3, 2), dtype=np.int64)

    for r in range(4):
        x = p[..., r * 4:r * 4 + 4]
        h33[..., r, 0] = x[..., 0] + x[..., 1] + x[..., 2]
        h33[..., r, 1] = x[..., 1] - x[..., 2] - x[..., 3]
        x = p[..., 16 + r * 3:16 + r * 3 + 3]
        h32[..., r, 0] = x[..., 0] + x[..., 1]
        h32[..., r, 1] = x[..., 1] + x[..., 2]

    for r in range(3):
        x = p[..., 28 + r * 4:28 + r * 4 + 4]
        h23[..., r, 0] = x[..., 0] + x[..., 1] + x[..., 2]
        h23[..., r, 1] = x[..., 1] - x[..., 2] - x[..., 3]
        x = p[..., 40 + r * 3:40 + r * 3 + 3]
        h22[..., r, 0] = x[..., 0] + x[..., 1]
        h22[..., r, 1] = x[..., 1] + x[..., 2]

    # Physical register widths in V24 P4.
    h33 = wrap_signed(h33, 26)
    h32 = wrap_signed(h32, 24)
    h23 = wrap_signed(h23, 24)
    h22 = wrap_signed(h22, 22)

    b0 = np.zeros(lead + (4,), dtype=np.int64)
    b1 = np.zeros(lead + (4,), dtype=np.int64)
    b2 = np.zeros(lead + (4,), dtype=np.int64)
    b3 = np.zeros(lead + (4,), dtype=np.int64)

    for col in range(2):
        # index order 00,01,10,11
        b0[..., col] = h33[..., 0, col] + h33[..., 1, col] + h33[..., 2, col]
        b0[..., 2 + col] = h33[..., 1, col] - h33[..., 2, col] - h33[..., 3, col]
        b1[..., col] = h32[..., 0, col] + h32[..., 1, col] + h32[..., 2, col]
        b1[..., 2 + col] = h32[..., 1, col] - h32[..., 2, col] - h32[..., 3, col]
        b2[..., col] = h23[..., 0, col] + h23[..., 1, col]
        b2[..., 2 + col] = h23[..., 1, col] + h23[..., 2, col]
        b3[..., col] = h22[..., 0, col] + h22[..., 1, col]
        b3[..., 2 + col] = h22[..., 1, col] + h22[..., 2, col]

    b0 = wrap_signed(b0, 27)
    b1 = wrap_signed(b1, 25)
    b2 = wrap_signed(b2, 25)
    b3 = wrap_signed(b3, 23)

    y = (b0 >> 2) + (b1 >> 1) + (b2 >> 1) + b3
    return wrap_signed(y, 29)


def transform_tiles_np(tiles: np.ndarray) -> np.ndarray:
    t = np.asarray(tiles, dtype=np.int64)
    flat = t.reshape(t.shape[:-2] + (36,))
    out = np.matmul(flat, B_MAT.T)
    # Apply exact lane activation register widths.
    for lane, aw in enumerate(LANE_AW.tolist()):
        out[..., lane] = wrap_signed(out[..., lane], int(aw))
    return out


def transform_kernels_np(kernels: np.ndarray) -> np.ndarray:
    k = np.asarray(kernels, dtype=np.int64)
    flat = k.reshape(k.shape[:-2] + (25,))
    return np.matmul(flat, G_MAT.T)


# -----------------------------------------------------------------------------
# Signed-power coefficient coding
# -----------------------------------------------------------------------------

def _candidate_terms(max_exp: int, scheme: str):
    # value -> (term_count, tuple(signed powers)) ; ties prefer fewer terms.
    best: Dict[int, Tuple[int, Tuple[int, ...]]] = {0: (0, tuple())}
    powers = [1 << e for e in range(max_exp + 1)]
    for p in powers:
        for s in (-1, 1):
            v = s * p
            best[v] = min(best.get(v, (99, tuple())), (1, (v,)), key=lambda z: z[0])
    if scheme in {"sp2", "csd2"}:
        for e1 in range(max_exp + 1):
            for e2 in range(e1):
                if scheme == "csd2" and abs(e1 - e2) == 1:
                    continue  # canonical signed-digit: no adjacent non-zero digits
                p1, p2 = 1 << e1, 1 << e2
                for s1 in (-1, 1):
                    for s2 in (-1, 1):
                        terms = (s1 * p1, s2 * p2)
                        v = sum(terms)
                        old = best.get(v)
                        if old is None or old[0] > 2:
                            best[v] = (2, terms)
    vals = sorted(best)
    return np.asarray(vals, dtype=np.int64), best


@lru_cache(maxsize=None)
def candidate_table(bits: int, scheme: str):
    if scheme == "exact":
        return None
    if scheme not in {"pot1", "sp2", "csd2"}:
        raise ValueError(f"unknown coefficient scheme {scheme}")
    max_abs = (1 << (bits - 1))
    max_exp = max(0, int(math.ceil(math.log2(max_abs))))
    vals, meta = _candidate_terms(max_exp, scheme)
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    vals = vals[(vals >= lo) & (vals <= hi)]
    return vals, meta


def quantize_signed_power(values: np.ndarray, bits_per_lane: np.ndarray | int, scheme: str):
    a = np.asarray(values, dtype=np.int64)
    if scheme == "exact":
        if np.ndim(bits_per_lane) == 0:
            return wrap_signed(a, int(bits_per_lane)), np.full_like(a, -1)
        out = np.empty_like(a)
        for lane, bits in enumerate(np.asarray(bits_per_lane).tolist()):
            out[..., lane] = wrap_signed(a[..., lane], int(bits))
        return out, np.full_like(a, -1)

    out = np.zeros_like(a)
    terms = np.zeros_like(a)
    if np.ndim(bits_per_lane) == 0:
        bits_arr = np.full(a.shape[-1] if a.ndim else 1, int(bits_per_lane), dtype=np.int64)
    else:
        bits_arr = np.asarray(bits_per_lane, dtype=np.int64)

    # Last dimension is treated as lanes if bits_per_lane is an array.
    if np.ndim(bits_per_lane) == 0:
        unique_vals = np.unique(a)
        vals, meta = candidate_table(int(bits_per_lane), scheme)
        lut = {}
        for x in unique_vals.tolist():
            idx = int(np.argmin(np.abs(vals - int(x))))
            q = int(vals[idx])
            lut[int(x)] = (q, meta[q][0])
        for x, (q, tc) in lut.items():
            m = (a == x)
            out[m] = q
            terms[m] = tc
        return out, terms

    for lane, bits in enumerate(bits_arr.tolist()):
        vals, meta = candidate_table(int(bits), scheme)
        src = a[..., lane]
        for x in np.unique(src).tolist():
            # Primary criterion: absolute numerical error. Secondary: fewer terms.
            errs = np.abs(vals - int(x))
            minerr = errs.min()
            idxs = np.flatnonzero(errs == minerr)
            if len(idxs) > 1:
                idx = min(idxs.tolist(), key=lambda ii: (meta[int(vals[ii])][0], abs(int(vals[ii]))))
            else:
                idx = int(idxs[0])
            q = int(vals[idx])
            tc = meta[q][0]
            m = (src == x)
            out[..., lane][m] = q
            terms[..., lane][m] = tc
    return out, terms


# -----------------------------------------------------------------------------
# Dataset / parameter loading
# -----------------------------------------------------------------------------

def _read_memh(path: Path, count: int, bits: int, signed: bool) -> np.ndarray:
    if not path.exists():
        raise FileNotFoundError(path)
    toks: List[str] = []
    for line in path.read_text().splitlines():
        line = line.split("//", 1)[0].strip()
        if not line:
            continue
        toks.extend(line.split())
    if len(toks) < count:
        raise ValueError(f"{path}: expected at least {count} values, got {len(toks)}")
    vals = []
    mask = (1 << bits) - 1
    for tok in toks[:count]:
        tok = tok.replace("_", "")
        # readmemh files are hexadecimal; tolerate 0x prefix.
        v = int(tok, 16) & mask
        if signed and (v & (1 << (bits - 1))):
            v -= 1 << bits
        vals.append(v)
    return np.asarray(vals, dtype=np.int64)


@dataclass
class ModelData:
    images: np.ndarray          # [N,28,28] uint-ish int64
    labels: np.ndarray          # [N]
    c1_w: np.ndarray            # [3,5,5]
    c1_b: np.ndarray            # [3]
    c2_w: np.ndarray            # [3,3,5,5] [out,in]
    c2_b: np.ndarray            # [3]
    fc_w: np.ndarray            # [10,48]
    fc_b: np.ndarray            # [10]


def load_model_data(data_dir: Path, num_images: int, label_file: str | None = None) -> ModelData:
    pixels = _read_memh(data_dir / "input_1000.txt", num_images * 784, 8, False)
    images = pixels.reshape(num_images, 28, 28)
    if label_file:
        labels = _read_memh(Path(label_file), num_images, 8, False)
    else:
        labels = np.arange(num_images, dtype=np.int64) % 10

    c1_w = np.stack([
        _read_memh(data_dir / f"conv1_weight_{i}.txt", 25, 8, True).reshape(5, 5)
        for i in (1, 2, 3)
    ])
    c1_b = _read_memh(data_dir / "conv1_bias.txt", 3, 8, True)

    c2 = np.zeros((3, 3, 5, 5), dtype=np.int64)
    for oc in range(3):
        for ic in range(3):
            c2[oc, ic] = _read_memh(
                data_dir / f"conv2_weight_{oc+1}{ic+1}.txt", 25, 8, True
            ).reshape(5, 5)
    c2_b = _read_memh(data_dir / "conv2_bias.txt", 3, 8, True)
    fc_w = _read_memh(data_dir / "fc_weight.txt", 480, 8, True).reshape(10, 48)
    fc_b = _read_memh(data_dir / "fc_bias.txt", 10, 8, True)
    return ModelData(images, labels, c1_w, c1_b, c2, c2_b, fc_w, fc_b)


# -----------------------------------------------------------------------------
# Search configuration
# -----------------------------------------------------------------------------
@dataclass(frozen=True)
class Config:
    wbits_c1: int = 7
    wbits_c2: int = 7
    wbits_fc: int = 7
    abits_f1: int = 11
    abits_f2: int = 11
    code_c1: str = "exact"
    code_c2: str = "exact"
    code_fc: str = "exact"
    prune_thr_c1: int = 0
    prune_thr_c2: int = 0
    prune_thr_fc: int = 0
    c1_mask: int = 0b111
    c2_mask: int = 0b111

    def tag(self) -> str:
        return (
            f"W{self.wbits_c1}{self.wbits_c2}{self.wbits_fc}_"
            f"A{self.abits_f1}{self.abits_f2}_"
            f"C{self.code_c1}-{self.code_c2}-{self.code_fc}_"
            f"T{self.prune_thr_c1}-{self.prune_thr_c2}-{self.prune_thr_fc}_"
            f"M{self.c1_mask:x}{self.c2_mask:x}"
        )


@dataclass
class EvalResult:
    config: Config
    correct: int
    total: int
    accuracy: float
    elapsed_s: float
    proxy_area: float
    proxy_dynamic: float
    proxy_ppa: float
    c1_zero_frac: float
    c2_zero_frac: float
    fc_zero_frac: float
    c1_avg_terms: float
    c2_avg_terms: float
    fc_avg_terms: float


# -----------------------------------------------------------------------------
# V24/V25 inference model
# -----------------------------------------------------------------------------
class Explorer:
    def __init__(self, data: ModelData):
        self.d = data
        # Conv1 raw-image transformed tiles do not depend on the candidate.
        sw = sliding_window_view(data.images, (6, 6), axis=(1, 2))
        c1_tiles = sw[:, ::2, ::2, :, :]  # [N,12,12,6,6]
        self.c1_bt = transform_tiles_np(c1_tiles)  # [N,12,12,49]
        self.cache: Dict[Config, EvalResult] = {}

    @staticmethod
    def _spatial_q(w: np.ndarray, bits: int, threshold: int) -> np.ndarray:
        x = np.asarray(w, dtype=np.int64).copy()
        if threshold > 0:
            x[np.abs(x) < threshold] = 0
        shift = 8 - bits
        return np.right_shift(x, shift)

    @staticmethod
    def _conv_td(kq: np.ndarray, bits: int, scheme: str):
        td = transform_kernels_np(kq)
        bw = LANE_BW_BASE - (8 - bits)
        q, terms = quantize_signed_power(td, bw, scheme)
        # Exact V24 physical P2 lane register widths.
        for lane, b in enumerate(bw.tolist()):
            q[..., lane] = wrap_signed(q[..., lane], int(b))
        return q, terms

    @staticmethod
    def _mul_inverse(bt: np.ndarray, coeff49: np.ndarray, wbits: int) -> np.ndarray:
        # bt [...,49], coeff49 [49]
        bw_shift = 8 - wbits
        pw = LANE_PW_BASE - bw_shift
        p = bt * coeff49
        for lane, bits in enumerate(pw.tolist()):
            p[..., lane] = wrap_signed(p[..., lane], int(bits))
        return inverse_pfdw(p)

    @staticmethod
    def _conv1_quant(raw: np.ndarray, bias: int, restore_shift: int) -> np.ndarray:
        t20 = wrap_signed(np.left_shift(raw, restore_shift), 20)
        shr = np.right_shift(t20, 8)
        return wrap_signed(shr + int(bias), 12)

    @staticmethod
    def _conv2_quant(sum20: np.ndarray, bias: int) -> np.ndarray:
        # RTL: sum20[19:6] then [13:1] == arithmetic >>7, then bias, low 12 bits.
        return wrap_signed(np.right_shift(wrap_signed(sum20, 20), 7) + int(bias), 12)

    @staticmethod
    def _pool_relu4(q4: np.ndarray) -> np.ndarray:
        m = np.max(q4, axis=-1)
        return np.where(m > 0, m, 0).astype(np.int64)

    @staticmethod
    def _fc_score(sum_prod: np.ndarray, bias: int, restore_shift: int) -> np.ndarray:
        t = wrap_signed(sum_prod, 20)
        t = wrap_signed(np.left_shift(t, restore_shift), 20)
        t = wrap_signed(t + int(bias), 20)
        return signed_slice(t, 18, 7)

    def _proxy(self, cfg: Config, td_stats: Dict[str, Tuple[np.ndarray, np.ndarray]], fq_terms: np.ndarray):
        # Transparent ranking proxy. It intentionally does NOT pretend to be OpenROAD.
        c1n, c2n = popcount3(cfg.c1_mask), popcount3(cfg.c2_mask)
        req_c1 = 144 * c1n
        req_c2 = 16 * c2n * c1n
        fc_lanes = 16 * c2n

        # Register/storage payload proxy.
        storage = 3 * 7 * 12 * cfg.abits_f1 + 3 * 4 * 4 * cfg.abits_f2
        storage += 36 * 8  # C1 window, common to all candidates

        def code_cost(scheme: str, terms: np.ndarray, abit: int, wbit: int):
            if scheme == "exact":
                # multiplier complexity proxy
                return float(abit * (wbit + 2))
            avg_terms = float(np.mean(terms)) if terms.size else 0.0
            # wiring/shift-select + optional add; much cheaper than a multiplier.
            return float(abit * (0.22 + 0.18 * avg_terms) + max(0.0, avg_terms - 1.0) * abit * 0.35)

        c1_terms = td_stats["c1"][1]
        c2_terms = td_stats["c2"][1]
        c1_pe = code_cost(cfg.code_c1, c1_terms, 14, cfg.wbits_c1)
        c2_pe = code_cost(cfg.code_c2, c2_terms, cfg.abits_f1 + 3, cfg.wbits_c2)
        fc_pe = code_cost(cfg.code_fc, fq_terms, cfg.abits_f2, cfg.wbits_fc)

        # Shared-PE area is dominated by the largest mode cost.
        pe_area = 49.0 * max(c1_pe, c2_pe, fc_pe)
        area = pe_area + 0.018 * storage + 110.0

        # Dynamic proxy weights how often each mode is exercised.
        dynamic = 49.0 * (req_c1 * c1_pe + req_c2 * c2_pe + 10 * (fc_lanes / 48.0) * fc_pe)
        dynamic /= 1e5
        # Channel pruning additionally reduces scheduler/accumulator activity.
        dynamic += 0.08 * (req_c1 + req_c2 + 10)
        ppa = area * dynamic
        return area, dynamic, ppa

    def evaluate(self, cfg: Config) -> EvalResult:
        if cfg in self.cache:
            return self.cache[cfg]
        t0 = time.time()
        d = self.d
        nimg = d.images.shape[0]

        # ---- weights: prune -> V24-style bit reduction ----
        c1q = self._spatial_q(d.c1_w, cfg.wbits_c1, cfg.prune_thr_c1)
        c2q = self._spatial_q(d.c2_w, cfg.wbits_c2, cfg.prune_thr_c2)
        fcq = self._spatial_q(d.fc_w, cfg.wbits_fc, cfg.prune_thr_fc)

        c1td, c1terms = self._conv_td(c1q, cfg.wbits_c1, cfg.code_c1)
        c2td, c2terms = self._conv_td(c2q, cfg.wbits_c2, cfg.code_c2)
        # FC does not use G transform.
        fcq_code, fcterms = quantize_signed_power(fcq, cfg.wbits_fc, cfg.code_fc)

        # ---- Conv1 + pool ----
        f1 = np.zeros((nimg, 3, 12, 12), dtype=np.int64)
        wshift1 = 8 - cfg.wbits_c1
        for oc in range(3):
            if not (cfg.c1_mask & (1 << oc)):
                continue
            y = self._mul_inverse(self.c1_bt, c1td[oc], cfg.wbits_c1)  # [N,12,12,4]
            q = self._conv1_quant(y, int(d.c1_b[oc]), wshift1)
            f1[:, oc] = self._pool_relu4(q)

        ashift1 = 11 - cfg.abits_f1
        if ashift1:
            f1 = np.right_shift(f1, ashift1)

        # ---- Conv2 + pool ----
        f2 = np.zeros((nimg, 3, 4, 4), dtype=np.int64)
        sw2 = sliding_window_view(f1, (6, 6), axis=(2, 3))
        tiles2 = sw2[:, :, ::2, ::2, :, :]  # [N,3,4,4,6,6]
        bt2 = transform_tiles_np(tiles2)     # [N,3,4,4,49]
        wshift2 = 8 - cfg.wbits_c2
        restore2 = ashift1 + wshift2

        for oc in range(3):
            if not (cfg.c2_mask & (1 << oc)):
                continue
            acc = np.zeros((nimg, 4, 4, 4), dtype=np.int64)
            for ic in range(3):
                if not (cfg.c1_mask & (1 << ic)):
                    continue
                y = self._mul_inverse(bt2[:, ic], c2td[oc, ic], cfg.wbits_c2)
                contrib = wrap_signed(np.left_shift(signed_slice(y, 19, 0), restore2), 20)
                acc = wrap_signed(acc + contrib, 20)
            q = self._conv2_quant(acc, int(d.c2_b[oc]))
            f2[:, oc] = self._pool_relu4(q)

        ashift2 = 11 - cfg.abits_f2
        if ashift2:
            f2 = np.right_shift(f2, ashift2)

        # ---- FC + online argmax equivalent ----
        flat = f2.reshape(nimg, 48)  # channel-major, row-major = V24 lane order
        scores = np.zeros((nimg, 10), dtype=np.int64)
        wshiftf = 8 - cfg.wbits_fc
        restoref = ashift2 + wshiftf
        # Inputs belonging to a pruned Conv2 output channel are already zero.
        for cls in range(10):
            prod_sum = np.sum(flat * fcq_code[cls][None, :], axis=1, dtype=np.int64)
            scores[:, cls] = self._fc_score(prod_sum, int(d.fc_b[cls]), restoref)
        pred = np.argmax(scores, axis=1)
        correct = int(np.sum(pred == d.labels))
        acc = correct / nimg

        td_stats = {"c1": (c1td, c1terms), "c2": (c2td, c2terms)}
        area, dyn, ppa = self._proxy(cfg, td_stats, fcterms)

        def zfrac(x):
            return float(np.mean(np.asarray(x) == 0))
        def avgterms(scheme, terms):
            if scheme == "exact":
                return float("nan")
            return float(np.mean(terms))

        res = EvalResult(
            config=cfg, correct=correct, total=nimg, accuracy=acc,
            elapsed_s=time.time() - t0,
            proxy_area=area, proxy_dynamic=dyn, proxy_ppa=ppa,
            c1_zero_frac=zfrac(c1td), c2_zero_frac=zfrac(c2td), fc_zero_frac=zfrac(fcq_code),
            c1_avg_terms=avgterms(cfg.code_c1, c1terms),
            c2_avg_terms=avgterms(cfg.code_c2, c2terms),
            fc_avg_terms=avgterms(cfg.code_fc, fcterms),
        )
        self.cache[cfg] = res
        return res

    def export_candidate(self, cfg: Config, out_dir: Path):
        out_dir.mkdir(parents=True, exist_ok=True)
        d = self.d
        c1q = self._spatial_q(d.c1_w, cfg.wbits_c1, cfg.prune_thr_c1)
        c2q = self._spatial_q(d.c2_w, cfg.wbits_c2, cfg.prune_thr_c2)
        fcq = self._spatial_q(d.fc_w, cfg.wbits_fc, cfg.prune_thr_fc)
        c1td, c1terms = self._conv_td(c1q, cfg.wbits_c1, cfg.code_c1)
        c2td, c2terms = self._conv_td(c2q, cfg.wbits_c2, cfg.code_c2)
        fcqc, fcterms = quantize_signed_power(fcq, cfg.wbits_fc, cfg.code_fc)

        (out_dir / "config.json").write_text(json.dumps(asdict(cfg), indent=2))
        np.savetxt(out_dir / "conv1_td_coeffs.csv", c1td.reshape(3, 49), fmt="%d", delimiter=",")
        np.savetxt(out_dir / "conv2_td_coeffs.csv", c2td.reshape(9, 49), fmt="%d", delimiter=",")
        np.savetxt(out_dir / "fc_coeffs.csv", fcqc.reshape(10, 48), fmt="%d", delimiter=",")
        np.savetxt(out_dir / "conv1_term_count.csv", c1terms.reshape(3, 49), fmt="%d", delimiter=",")
        np.savetxt(out_dir / "conv2_term_count.csv", c2terms.reshape(9, 49), fmt="%d", delimiter=",")
        np.savetxt(out_dir / "fc_term_count.csv", fcterms.reshape(10, 48), fmt="%d", delimiter=",")

    def validate_known(self):
        print("[validate] checking V21/W8 and V24/W7 software-model points...")
        r8 = self.evaluate(Config(wbits_c1=8, wbits_c2=8, wbits_fc=8))
        r7 = self.evaluate(Config())
        print(f"  W8 exact: {r8.correct}/{r8.total} = {100*r8.accuracy:.2f}%")
        print(f"  W7 exact: {r7.correct}/{r7.total} = {100*r7.accuracy:.2f}%")
        if r8.total == 1000:
            if r8.correct != 970 or r7.correct != 980:
                print("  WARNING: expected project checkpoints are W8=970/1000 and W7=980/1000.")
                print("           Do NOT trust a broad search until file ordering/data format is checked.")
                return False
            print("  PASS: matches the known V21/V24 1000-image checkpoints.")
        else:
            print("  NOTE: exact 97/98% checkpoint only applies to the full 1000-image run.")
        return True


# -----------------------------------------------------------------------------
# Search routines
# -----------------------------------------------------------------------------
def result_row(r: EvalResult):
    d = asdict(r.config)
    d.update({
        "correct": r.correct,
        "total": r.total,
        "accuracy": r.accuracy,
        "accuracy_pct": 100 * r.accuracy,
        "elapsed_s": r.elapsed_s,
        "proxy_area": r.proxy_area,
        "proxy_dynamic": r.proxy_dynamic,
        "proxy_ppa": r.proxy_ppa,
        "c1_zero_frac": r.c1_zero_frac,
        "c2_zero_frac": r.c2_zero_frac,
        "fc_zero_frac": r.fc_zero_frac,
        "c1_avg_terms": r.c1_avg_terms,
        "c2_avg_terms": r.c2_avg_terms,
        "fc_avg_terms": r.fc_avg_terms,
        "tag": r.config.tag(),
    })
    return d


def save_results(results: Sequence[EvalResult], out_csv: Path):
    rows = [result_row(r) for r in results]
    if not rows:
        return
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def print_result(r: EvalResult, prefix=""):
    print(
        f"{prefix}{r.config.tag():58s} "
        f"acc={100*r.accuracy:6.2f}% ({r.correct}/{r.total}) "
        f"Aproxy={r.proxy_area:8.1f} Dproxy={r.proxy_dynamic:9.1f} "
        f"PPA={r.proxy_ppa:11.1f} t={r.elapsed_s:5.2f}s"
    )


def coordinate_search(ex: Explorer, min_acc: float, out_dir: Path, passes: int = 2):
    # Start from the measured V24 W7 design point.
    current = Config()
    all_results: List[EvalResult] = []
    rcur = ex.evaluate(current)
    all_results.append(rcur)
    print_result(rcur, "START ")

    fields = [
        ("wbits_c1", [4, 5, 6, 7, 8]),
        ("wbits_c2", [4, 5, 6, 7, 8]),
        ("wbits_fc", [4, 5, 6, 7, 8]),
        ("abits_f1", [8, 9, 10, 11]),
        ("abits_f2", [8, 9, 10, 11]),
        # sp2 is intentionally included separately from strict CSD2.
        ("code_c1", ["exact", "sp2", "csd2", "pot1"]),
        ("code_c2", ["exact", "sp2", "csd2", "pot1"]),
        ("code_fc", ["exact", "sp2", "csd2", "pot1"]),
        ("prune_thr_c1", [0, 2, 4, 8, 16, 32]),
        ("prune_thr_c2", [0, 2, 4, 8, 16, 32]),
        ("prune_thr_fc", [0, 2, 4, 8, 16, 32]),
        # Keep all channels or remove one. Multiple-channel removal can be tried
        # manually after the first robust candidate is found.
        ("c1_mask", [0b111, 0b110, 0b101, 0b011]),
        ("c2_mask", [0b111, 0b110, 0b101, 0b011]),
    ]

    for pidx in range(passes):
        print(f"\n=== coordinate pass {pidx+1}/{passes} ===")
        changed = False
        for field, values in fields:
            candidates = []
            seen = set()
            for v in values:
                c = replace(current, **{field: v})
                if c in seen:
                    continue
                seen.add(c)
                r = ex.evaluate(c)
                all_results.append(r)
                candidates.append(r)
                print_result(r, f"  {field:13s} ")
            feasible = [r for r in candidates if r.accuracy >= min_acc]
            if feasible:
                best = min(feasible, key=lambda r: (r.proxy_ppa, r.proxy_area, -r.accuracy))
                if best.config != current:
                    print(f"  -> accept {field}={getattr(best.config, field)}")
                    current = best.config
                    rcur = best
                    changed = True
            else:
                print(f"  -> no {field} candidate meets min accuracy {100*min_acc:.2f}%")
        if not changed:
            break

    # De-duplicate and rank feasible results.
    uniq = {r.config: r for r in all_results}
    all_results = list(uniq.values())
    feasible = sorted(
        [r for r in all_results if r.accuracy >= min_acc],
        key=lambda r: (r.proxy_ppa, r.proxy_area, -r.accuracy)
    )
    save_results(sorted(all_results, key=lambda r: (-r.accuracy, r.proxy_ppa)), out_dir / "v25_search_results.csv")

    print("\n=== TOP FEASIBLE CANDIDATES ===")
    for r in feasible[:12]:
        print_result(r, "TOP   ")
    if feasible:
        best = feasible[0]
        (out_dir / "v25_best_config.json").write_text(json.dumps(result_row(best), indent=2))
        ex.export_candidate(best.config, out_dir / "best_candidate_export")
        print(f"\nBest config exported to: {out_dir / 'best_candidate_export'}")
        return best
    print("No candidate met the minimum accuracy target.")
    return None


# -----------------------------------------------------------------------------
# Self-test
# -----------------------------------------------------------------------------
def selftest():
    rng = np.random.default_rng(7)
    for _ in range(30):
        tile = rng.integers(-20, 21, size=(6, 6), dtype=np.int64)
        ker = rng.integers(-8, 9, size=(5, 5), dtype=np.int64)
        bt = transform_tiles_np(tile[None, ...])[0]
        gt = transform_kernels_np(ker[None, ...])[0]
        p = bt * gt
        # W8 exact physical lane widths.
        for lane, pw in enumerate(LANE_PW_BASE.tolist()):
            p[lane] = wrap_signed(p[lane], int(pw))
        y = inverse_pfdw(p[None, ...])[0]
        direct = []
        for ro, co in ((0, 0), (0, 1), (1, 0), (1, 1)):
            direct.append(int(np.sum(tile[ro:ro+5, co:co+5] * ker)))
        if list(map(int, y)) != direct:
            raise AssertionError((y.tolist(), direct))
    print("SELFTEST PASS: PFDW integer transform reproduces direct 5x5 convolution.")


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    ap.add_argument("--data-dir", type=Path, help="directory containing input_1000.txt and weight/bias txt files")
    ap.add_argument("--num-images", type=int, default=200, help="number of images to evaluate (1..1000)")
    ap.add_argument("--label-file", type=str, default=None, help="optional readmemh label file; otherwise label=index%%10")
    ap.add_argument("--out-dir", type=Path, default=Path("v25_search_out"))
    ap.add_argument("--min-acc", type=float, default=0.97, help="minimum acceptable accuracy, fraction")
    ap.add_argument("--passes", type=int, default=2, help="coordinate-search passes")
    ap.add_argument("--validate", action="store_true", help="evaluate W8 and W7 project checkpoints")
    ap.add_argument("--search", action="store_true", help="run coordinate search")
    ap.add_argument("--selftest", action="store_true", help="run arithmetic self-test and exit if no data-dir")
    args = ap.parse_args()

    selftest()
    if args.selftest and args.data_dir is None:
        return
    if args.data_dir is None:
        ap.error("--data-dir is required unless only --selftest is requested")
    if not (1 <= args.num_images <= 1000):
        ap.error("--num-images must be 1..1000")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Loading {args.num_images} images from {args.data_dir} ...")
    data = load_model_data(args.data_dir, args.num_images, args.label_file)
    ex = Explorer(data)

    if args.validate or not args.search:
        ex.validate_known()
    if args.search:
        best = coordinate_search(ex, args.min_acc, args.out_dir, args.passes)
        if best is not None:
            print("\nIMPORTANT: proxy ranking is not an OpenROAD PPA result.")
            print("Synthesize at least the top 3 feasible candidates before selecting V25 RTL.")


if __name__ == "__main__":
    main()
