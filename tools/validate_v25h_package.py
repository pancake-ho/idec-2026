#!/usr/bin/env python3
from pathlib import Path
import importlib.util
import json
import re
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "reference"
RTL = ROOT / "rtl" / "pfdw_pipe49_shift_engine_v25h.sv"
EXP = ROOT / "tools" / "explore_v25.py"

spec = importlib.util.spec_from_file_location("v25explorer", EXP)
ex = importlib.util.module_from_spec(spec)
sys.modules["v25explorer"] = ex
spec.loader.exec_module(ex)


def signed_literal(text: str) -> int:
    m = re.search(r"(?P<neg>-)?8'sd(?P<num>\d+)", text)
    if not m:
        raise ValueError(f"cannot parse signed literal: {text}")
    v = int(m.group("num"))
    return -v if m.group("neg") else v


def bits_for(lo: int, hi: int) -> int:
    for b in range(1, 63):
        if lo >= -(1 << (b - 1)) and hi <= (1 << (b - 1)) - 1:
            return b
    raise ValueError((lo, hi))


def add(*xs):
    return (sum(x[0] for x in xs), sum(x[1] for x in xs))


def neg(x):
    return (-x[1], -x[0])


def mul_interval(lo, hi, c):
    x, y = lo * c, hi * c
    return (min(x, y), max(x, y))


def main():
    s = RTL.read_text()
    c1 = np.loadtxt(REF / "conv1_td_coeffs.csv", delimiter=",", dtype=int)
    c2 = np.loadtxt(REF / "conv2_td_coeffs.csv", delimiter=",", dtype=int)
    fc = np.loadtxt(REF / "fc_coeffs.csv", delimiter=",", dtype=int)
    manifest = json.loads((REF / "v25h_manifest.json").read_text())

    # 1) Verify every embedded RTL coefficient against exported search artifacts.
    lane_marks = list(re.finditer(r"if \(1\) begin : G_LANE_(\d+)\n", s))
    assert len(lane_marks) == 49, f"expected 49 lanes, found {len(lane_marks)}"
    errors = []
    for idx, mark in enumerate(lane_marks):
        lane = int(mark.group(1))
        end = lane_marks[idx + 1].start() if idx + 1 < len(lane_marks) else s.index("    logic p4_valid", mark.start())
        block = s[mark.start():end]

        fc_map = {int(k): signed_literal(v) for k, v in re.findall(r"5'd(\d+): coeff_term = ([^;]+);", block)}
        for cls in range(10):
            got = fc_map.get(cls, 0) + fc_map.get(16 + cls, 0)
            expected = int(fc[cls, lane]) if lane < 48 else 0
            if got != expected:
                errors.append(("fc", lane, cls, got, expected))

        m = re.search(
            r"end else if \(!p2_tag\[15\]\) begin\s*case \(p2_tag\[3:2\]\)(.*?)endcase\s*"
            r"end else begin\s*case \(\{p2_tag\[3:2\],p2_tag\[1:0\]\}\)(.*?)endcase",
            block, re.S,
        )
        assert m, f"could not parse Conv tables for lane {lane}"
        c1_map = {int(k): signed_literal(v) for k, v in re.findall(r"2'd(\d+): coeff_term = ([^;]+);", m.group(1))}
        for phys, orig in ((0, 1), (1, 2)):
            got, expected = c1_map.get(phys, 0), int(c1[orig, lane])
            if got != expected:
                errors.append(("c1", lane, phys, got, expected))

        c2_map = {int(k, 2): signed_literal(v) for k, v in re.findall(r"4'b([01]{4}): coeff_term = ([^;]+);", m.group(2))}
        c2r = c2.reshape(3, 3, 49)
        for oc in range(3):
            for phys, orig_ic in ((0, 1), (1, 2)):
                key = (oc << 2) | phys
                got, expected = c2_map.get(key, 0), int(c2r[oc, orig_ic, lane])
                if got != expected:
                    errors.append(("c2", lane, oc, phys, got, expected))
    assert not errors, f"embedded coefficient mismatches: {errors[:10]}"

    # 2) Prove lane product widths for all independent unsigned 8-bit pixels.
    B = ex.B_MAT
    bmin = np.where(B < 0, B * 255, 0).sum(axis=1)
    bmax = np.where(B > 0, B * 255, 0).sum(axis=1)
    kernels = np.concatenate([c1[1:3], c2.reshape(3, 3, 49)[:, 1:3, :].reshape(6, 49)], axis=0)
    pmins, pmaxs = [], []
    for k in kernels:
        los, his = [], []
        for lane, coeff in enumerate(k):
            lo, hi = mul_interval(int(bmin[lane]), int(bmax[lane]), int(coeff))
            los.append(lo); his.append(hi)
        pmins.append(los); pmaxs.append(his)
    pmins, pmaxs = np.asarray(pmins), np.asarray(pmaxs)
    required_pw = [bits_for(int(pmins[:, i].min()), int(pmaxs[:, i].max())) for i in range(49)]
    declared_pw = manifest["lane_product_bits"]
    assert required_pw == declared_pw, "lane product width proof does not match manifest"

    # 3) Conservative interval proof for P4/P5 inverse-transform registers.
    p4_max = {"h33": 0, "h32": 0, "h23": 0, "h22": 0}
    p5_max = {"b0": 0, "b1": 0, "b2": 0, "b3": 0}
    y_bits = 0
    for ki in range(len(kernels)):
        p = [(int(pmins[ki, i]), int(pmaxs[ki, i])) for i in range(49)]
        h33 = []; h32 = []; h23 = []; h22 = []
        for r in range(4):
            x = p[r*4:r*4+4]
            h33.append((add(*x[:3]), add(x[1], neg(x[2]), neg(x[3]))))
            x = p[16+r*3:16+r*3+3]
            h32.append((add(*x[:2]), add(*x[1:3])))
        for r in range(3):
            x = p[28+r*4:28+r*4+4]
            h23.append((add(*x[:3]), add(x[1], neg(x[2]), neg(x[3]))))
            x = p[40+r*3:40+r*3+3]
            h22.append((add(*x[:2]), add(*x[1:3])))
        for name, arr in (("h33", h33), ("h32", h32), ("h23", h23), ("h22", h22)):
            flat = [z for pair in arr for z in pair]
            p4_max[name] = max(p4_max[name], bits_for(min(z[0] for z in flat), max(z[1] for z in flat)))

        def va3(arr):
            out = []
            for col in (0, 1):
                xs = [arr[r][col] for r in range(4)]
                out += [add(*xs[:3]), add(xs[1], neg(xs[2]), neg(xs[3]))]
            return out
        def va2(arr):
            out = []
            for col in (0, 1):
                xs = [arr[r][col] for r in range(3)]
                out += [add(*xs[:2]), add(*xs[1:3])]
            return out
        blocks = [va3(h33), va3(h32), va2(h23), va2(h22)]
        for name, arr in zip(("b0", "b1", "b2", "b3"), blocks):
            p5_max[name] = max(p5_max[name], bits_for(min(z[0] for z in arr), max(z[1] for z in arr)))
        for j in range(4):
            shr = lambda z, n: (z[0] >> n, z[1] >> n)
            y = add(shr(blocks[0][j], 2), shr(blocks[1][j], 1), shr(blocks[2][j], 1), blocks[3][j])
            y_bits = max(y_bits, bits_for(*y))

    assert p4_max == {"h33":18, "h32":17, "h23":17, "h22":15}, p4_max
    assert p5_max == {"b0":19, "b1":18, "b2":18, "b3":16}, p5_max
    assert y_bits <= 20

    # 4) FC SP2 decomposition/range proof.
    _, meta = ex.candidate_table(6, "sp2")
    terms = np.zeros((10, 48, 2), dtype=int)
    for cls in range(10):
        for lane in range(48):
            ts = meta[int(fc[cls, lane])][1]
            terms[cls, lane, :len(ts)] = ts
    full_ranges = []
    for term in (0, 1):
        class_ranges = []
        for cls in range(10):
            ints = [mul_interval(0, 255, int(terms[cls, lane, term])) for lane in range(48)]
            class_ranges.append(add(*ints))
        full_ranges.append((min(x[0] for x in class_ranges), max(x[1] for x in class_ranges)))
    assert bits_for(*full_ranges[0]) <= 16
    assert bits_for(*full_ranges[1]) <= 16

    print("V25-H PACKAGE VALIDATION PASS")
    print("  embedded coefficient tables : exact match")
    print("  Conv lane product widths    : proven for all input bytes 0..255")
    print("  P4/P5 inverse widths        : conservative interval proof PASS")
    print(f"  FC temporal pass ranges     : term0={full_ranges[0]}, term1={full_ranges[1]}")
    print("  NOTE: this is structural/numerical validation, not an RTL simulator.")

if __name__ == "__main__":
    main()
