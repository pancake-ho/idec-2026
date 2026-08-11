from __future__ import annotations

import argparse
import csv
from pathlib import Path

from config import TABLE_DIR


DEFAULT_PYTHON = (
    TABLE_DIR
    / "baseline_predictions.csv"
)

DEFAULT_RTL = (
    Path(__file__).resolve().parent
    / "outputs"
    / "rtl_predictions.csv"
)

DEFAULT_OUTPUT = (
    TABLE_DIR
    / "rtl_python_comparison.csv"
)


def load_python_predictions(
    path: Path,
):
    rows = {}

    with path.open(
        "r",
        encoding="utf-8",
        newline="",
    ) as f:

        reader = csv.DictReader(f)

        required = {
            "image_index",
            "expected",
            "predicted",
        }

        if not required.issubset(
            set(reader.fieldnames or [])
        ):
            raise ValueError(
                f"{path}: missing required columns. "
                f"Found {reader.fieldnames}"
            )

        for row in reader:

            idx = int(
                row["image_index"]
            )

            if idx in rows:
                raise ValueError(
                    f"Duplicate Python image index {idx}"
                )

            rows[idx] = {
                "expected": int(
                    row["expected"]
                ),
                "predicted": int(
                    row["predicted"]
                ),
            }

    return rows


def load_rtl_predictions(
    path: Path,
):
    rows = {}

    with path.open(
        "r",
        encoding="utf-8",
        newline="",
    ) as f:

        reader = csv.DictReader(f)

        required = {
            "image_index",
            "expected",
            "predicted",
            "cycles",
        }

        if not required.issubset(
            set(reader.fieldnames or [])
        ):
            raise ValueError(
                f"{path}: missing required columns. "
                f"Found {reader.fieldnames}"
            )

        for row in reader:

            idx = int(
                row["image_index"]
            )

            if idx in rows:
                raise ValueError(
                    f"Duplicate RTL image index {idx}"
                )

            rows[idx] = {
                "expected": int(
                    row["expected"]
                ),
                "predicted": int(
                    row["predicted"]
                ),
                "cycles": int(
                    row["cycles"]
                ),
            }

    return rows


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--python",
        type=Path,
        default=DEFAULT_PYTHON,
    )

    parser.add_argument(
        "--rtl",
        type=Path,
        default=DEFAULT_RTL,
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
    )

    parser.add_argument(
        "--show",
        type=int,
        default=30,
    )

    args = parser.parse_args()

    py_rows = load_python_predictions(
        args.python
    )

    rtl_rows = load_rtl_predictions(
        args.rtl
    )

    py_indices = set(
        py_rows.keys()
    )

    rtl_indices = set(
        rtl_rows.keys()
    )

    if py_indices != rtl_indices:

        missing_in_rtl = sorted(
            py_indices - rtl_indices
        )

        missing_in_python = sorted(
            rtl_indices - py_indices
        )

        raise ValueError(
            "Prediction index sets differ.\n"
            f"Missing in RTL: {missing_in_rtl[:20]}\n"
            f"Missing in Python: {missing_in_python[:20]}"
        )

    indices = sorted(
        py_indices
    )

    output_rows = []

    prediction_mismatches = []
    label_mismatches = []

    python_correct = 0
    rtl_correct = 0

    cycles = []

    for idx in indices:

        py = py_rows[idx]
        rtl = rtl_rows[idx]

        if (
            py["expected"]
            != rtl["expected"]
        ):
            label_mismatches.append(
                idx
            )

        same_prediction = (
            py["predicted"]
            == rtl["predicted"]
        )

        if not same_prediction:
            prediction_mismatches.append(
                idx
            )

        py_ok = (
            py["predicted"]
            == py["expected"]
        )

        rtl_ok = (
            rtl["predicted"]
            == rtl["expected"]
        )

        python_correct += int(
            py_ok
        )

        rtl_correct += int(
            rtl_ok
        )

        cycles.append(
            rtl["cycles"]
        )

        output_rows.append(
            {
                "image_index": idx,
                "expected": py["expected"],
                "python_pred": py["predicted"],
                "rtl_pred": rtl["predicted"],
                "prediction_equal": int(
                    same_prediction
                ),
                "python_correct": int(
                    py_ok
                ),
                "rtl_correct": int(
                    rtl_ok
                ),
                "rtl_cycles": rtl["cycles"],
            }
        )

    args.output.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with args.output.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=list(
                output_rows[0].keys()
            ),
        )

        writer.writeheader()
        writer.writerows(
            output_rows
        )

    print()
    print("=" * 72)
    print("RTL <-> PYTHON IMAGE-WISE EQUIVALENCE")
    print("=" * 72)

    print(
        f"Images                  : {len(indices)}"
    )

    print(
        f"Python correct          : "
        f"{python_correct}/{len(indices)}"
    )

    print(
        f"RTL correct             : "
        f"{rtl_correct}/{len(indices)}"
    )

    print(
        f"Prediction equal        : "
        f"{len(indices) - len(prediction_mismatches)}"
        f"/{len(indices)}"
    )

    print(
        f"Prediction mismatches   : "
        f"{len(prediction_mismatches)}"
    )

    print(
        f"Label mismatches        : "
        f"{len(label_mismatches)}"
    )

    if cycles:

        print(
            f"RTL cycles min/max      : "
            f"{min(cycles)} / {max(cycles)}"
        )

    if prediction_mismatches:

        print()
        print("First prediction mismatches:")

        for idx in prediction_mismatches[
            :args.show
        ]:

            print(
                f"  image={idx:4d} "
                f"expected={py_rows[idx]['expected']} "
                f"python={py_rows[idx]['predicted']} "
                f"rtl={rtl_rows[idx]['predicted']}"
            )

    print()
    print(f"Saved comparison       : {args.output}")

    print("=" * 72)

    if (
        len(prediction_mismatches) == 0
        and len(label_mismatches) == 0
    ):
        print(
            "PASS: RTL and Python predictions are "
            "image-wise equivalent."
        )
    else:
        print(
            "FAIL: Do not proceed to quantization yet."
        )


if __name__ == "__main__":
    main()