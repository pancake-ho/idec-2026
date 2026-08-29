#!/usr/bin/env python3
"""Search hardware-cheap power-of-two weight precision candidates.

The candidate RTL keeps the official 8-bit weight ports, maps each layer to a
narrow signed integer, uses it in the shared PFDW multipliers, and restores the
common power-of-two scale after the MAC.  The three supported mappings are
floor, truncate-to-zero, and round-to-nearest-even.  This script models:

    q = quantize(weight / 2**(8 - bits))
    effective_weight = q <<< (8 - bits)

No floating-point scale, divider, retraining, or hidden calibration data is
used.  Decisions are compared with the repository's bit-exact RTL model.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PACKAGE_ROOT.parent
ANALYZE_DIR = REPO_ROOT / "analyze"

sys.path.insert(0, str(ANALYZE_DIR))

from io_utils import (  # noqa: E402
    RTLParameters,
    labels_for_input_1000,
    load_input_1000,
    load_parameters,
)
from rtl_model import RTLReferenceCNN  # noqa: E402


def parse_bits(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        bits = int(token.strip())
        if bits < 3 or bits > 8:
            raise argparse.ArgumentTypeError("weight bits must be in [3, 8]")
        if bits not in result:
            result.append(bits)
    if not result:
        raise argparse.ArgumentTypeError("at least one bit width is required")
    return result


def pow2_quantize(
    values: np.ndarray,
    bits: int,
    mode: str,
) -> tuple[np.ndarray, np.ndarray]:
    """Return narrow q and reconstructed value for one RTL rounding mode."""
    shift = 8 - bits
    values = np.asarray(values, dtype=np.int64)
    scale = 1 << shift
    if mode == "floor":
        q = values >> shift
    elif mode == "trunc":
        q = np.trunc(values / scale).astype(np.int64)
    elif mode == "even":
        q = np.rint(values / scale).astype(np.int64)
    else:
        raise ValueError(f"unsupported mode: {mode}")
    q_min = -(1 << (bits - 1))
    q_max = (1 << (bits - 1)) - 1
    q = np.clip(q, q_min, q_max)
    return q, q << shift


def quantized_parameters(
    params: RTLParameters,
    bits: int,
    modes: tuple[str, str, str],
) -> RTLParameters:
    _, conv1_w = pow2_quantize(params.conv1_w, bits, modes[0])
    _, conv2_w = pow2_quantize(params.conv2_w, bits, modes[1])
    _, fc_w = pow2_quantize(params.fc_w, bits, modes[2])
    return replace(
        params,
        conv1_w=conv1_w,
        conv2_w=conv2_w,
        fc_w=fc_w,
    )


def predict(model: RTLReferenceCNN, images: np.ndarray) -> np.ndarray:
    return np.asarray(
        [model.forward(image, return_trace=False) for image in images],
        dtype=np.int64,
    )


def layer_stats(
    name: str,
    values: np.ndarray,
    bits: int,
    mode: str,
) -> dict[str, object]:
    q, reconstructed = pow2_quantize(values, bits, mode)
    error = reconstructed - np.asarray(values, dtype=np.int64)
    return {
        "layer": name,
        "bits": bits,
        "mode": mode,
        "shift": 8 - bits,
        "q_min": int(q.min()),
        "q_max": int(q.max()),
        "nonzero_q": int(np.count_nonzero(q)),
        "weights": int(q.size),
        "mae": float(np.mean(np.abs(error))),
        "max_abs_error": int(np.max(np.abs(error))),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bits", type=parse_bits, default=parse_bits("8,7,6,5,4"))
    parser.add_argument("--dataset", type=Path, default=REPO_ROOT / "data/input_1000.txt")
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--min-correct", type=int, default=970)
    parser.add_argument(
        "--exhaustive",
        action="store_true",
        help="try all floor/trunc/even layer-mode combinations",
    )
    parser.add_argument("--output-dir", type=Path, default=PACKAGE_ROOT / "build/search")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    images = load_input_1000(args.dataset)
    if args.limit is not None:
        images = images[: args.limit]
    labels = labels_for_input_1000(len(images))
    params = load_parameters(REPO_ROOT / "data")

    baseline_predictions = predict(RTLReferenceCNN(params), images)
    baseline_correct = int(np.count_nonzero(baseline_predictions == labels))

    rows: list[dict[str, object]] = []
    details: dict[str, object] = {
        "dataset": str(args.dataset),
        "images": len(images),
        "baseline_correct": baseline_correct,
        "baseline_accuracy_percent": 100.0 * baseline_correct / len(images),
        "candidates": [],
    }

    print(f"Baseline: {baseline_correct}/{len(images)}")
    curated = {
        8: [("floor", "floor", "floor")],
        7: [("floor", "floor", "floor")],
        6: [("floor", "even", "floor")],
        5: [("floor", "trunc", "even")],
        4: [("trunc", "even", "even")],
    }
    candidates = []
    for bits in args.bits:
        modes_list = (
            list(itertools.product(("floor", "trunc", "even"), repeat=3))
            if args.exhaustive and bits != 8
            else curated[bits]
        )
        candidates.extend((bits, modes) for modes in modes_list)

    for bits, modes in candidates:
        candidate_params = quantized_parameters(params, bits, modes)
        predictions = predict(RTLReferenceCNN(candidate_params), images)
        correct = int(np.count_nonzero(predictions == labels))
        decision_match = int(np.count_nonzero(predictions == baseline_predictions))
        passed = correct >= args.min_correct
        row = {
            "bits": bits,
            "shift": 8 - bits,
            "conv1_mode": modes[0],
            "conv2_mode": modes[1],
            "fc_mode": modes[2],
            "correct": correct,
            "accuracy_percent": 100.0 * correct / len(images),
            "decision_match": decision_match,
            "decision_mismatch": len(images) - decision_match,
            "gate": "PASS" if passed else "FAIL",
        }
        rows.append(row)
        candidate_detail = dict(row)
        candidate_detail["layers"] = [
            layer_stats("conv1", params.conv1_w, bits, modes[0]),
            layer_stats("conv2", params.conv2_w, bits, modes[1]),
            layer_stats("fc", params.fc_w, bits, modes[2]),
        ]
        details["candidates"].append(candidate_detail)
        print(
            f"W{bits} {modes}: correct={correct}/{len(images)} "
            f"match={decision_match}/{len(images)} gate={row['gate']}"
        )

    passing = [row for row in rows if row["gate"] == "PASS"]
    selected = (
        min(
            passing,
            key=lambda row: (int(row["bits"]), -int(row["correct"])),
        )
        if passing
        else None
    )
    details["selection"] = selected

    args.output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_dir / "pow2_mp_search.csv"
    json_path = args.output_dir / "pow2_mp_search.json"
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    json_path.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")

    if selected is None:
        print("SELECTED: none")
        return 1
    print(
        f"SELECTED: W{selected['bits']} shift={selected['shift']} "
        f"modes=({selected['conv1_mode']},{selected['conv2_mode']},"
        f"{selected['fc_mode']})"
    )
    print(f"CSV: {csv_path}")
    print(f"JSON: {json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
