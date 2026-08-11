from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from config import (
    DATA_DIR,
    DEFAULT_DATASET,
    TABLE_DIR,
)

from fixed_point import (
    required_signed_bits,
    required_unsigned_bits,
)

from io_utils import (
    load_parameters,
    load_input_1000,
)

from rtl_model import RTLReferenceCNN


@dataclass
class RangeStats:
    count: int = 0
    zero_count: int = 0

    min_value: int | None = None
    max_value: int | None = None

    def update(
        self,
        values,
    ):
        values = np.asarray(
            values,
            dtype=np.int64,
        )

        if values.size == 0:
            return

        current_min = int(
            values.min()
        )

        current_max = int(
            values.max()
        )

        if self.min_value is None:
            self.min_value = current_min
        else:
            self.min_value = min(
                self.min_value,
                current_min,
            )

        if self.max_value is None:
            self.max_value = current_max
        else:
            self.max_value = max(
                self.max_value,
                current_max,
            )

        self.count += int(
            values.size
        )

        self.zero_count += int(
            np.count_nonzero(values == 0)
        )

    @property
    def zero_ratio(self) -> float:
        if self.count == 0:
            return 0.0

        return (
            self.zero_count
            / self.count
        )


def required_bits(
    stats: RangeStats,
    signed: bool,
) -> int | None:

    if (
        stats.min_value is None
        or stats.max_value is None
    ):
        return None

    if signed:
        return required_signed_bits(
            stats.min_value,
            stats.max_value,
        )

    if stats.min_value < 0:
        raise ValueError(
            "Unsigned tensor contains negative value: "
            f"{stats.min_value}"
        )

    return required_unsigned_bits(
        stats.max_value
    )


def make_row(
    name: str,
    stats: RangeStats,
    declared_bits: int | None,
    signed: bool,
):
    return {
        "name": name,
        "declared_bits": (
            ""
            if declared_bits is None
            else declared_bits
        ),
        "signed": int(signed),
        "min": stats.min_value,
        "max": stats.max_value,
        "required_bits": required_bits(
            stats,
            signed,
        ),
        "count": stats.count,
        "zero_count": stats.zero_count,
        "zero_ratio": stats.zero_ratio,
    }


def stats_from_array(
    array,
) -> RangeStats:

    stats = RangeStats()

    stats.update(array)

    return stats


def save_csv(
    path: Path,
    rows: list[dict],
):
    if not rows:
        return

    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=list(
                rows[0].keys()
            ),
        )

        writer.writeheader()
        writer.writerows(rows)


def print_rows(
    title: str,
    rows: list[dict],
):
    print()
    print("=" * 100)
    print(title)
    print("=" * 100)

    header = (
        f"{'Tensor':<24}"
        f"{'RTL':>7}"
        f"{'Need':>7}"
        f"{'Min':>12}"
        f"{'Max':>12}"
        f"{'Zero %':>12}"
    )

    print(header)
    print("-" * 100)

    for row in rows:

        rtl_bits = row[
            "declared_bits"
        ]

        need_bits = row[
            "required_bits"
        ]

        print(
            f"{row['name']:<24}"
            f"{str(rtl_bits):>7}"
            f"{str(need_bits):>7}"
            f"{str(row['min']):>12}"
            f"{str(row['max']):>12}"
            f"{100.0 * row['zero_ratio']:>11.2f}%"
        )

    print("=" * 100)


def analyze_weights(
    params,
):
    specs = [
        (
            "Conv1 weight",
            params.conv1_w,
            8,
            True,
        ),
        (
            "Conv1 bias",
            params.conv1_b,
            8,
            True,
        ),
        (
            "Conv2 weight",
            params.conv2_w,
            8,
            True,
        ),
        (
            "Conv2 bias",
            params.conv2_b,
            8,
            True,
        ),
        (
            "FC weight",
            params.fc_w,
            8,
            True,
        ),
        (
            "FC bias",
            params.fc_b,
            8,
            True,
        ),
    ]

    rows = []

    for (
        name,
        array,
        declared,
        signed,
    ) in specs:

        stats = stats_from_array(
            array
        )

        rows.append(
            make_row(
                name=name,
                stats=stats,
                declared_bits=declared,
                signed=signed,
            )
        )

    return rows


def analyze_activations(
    model: RTLReferenceCNN,
    images: np.ndarray,
):
    collectors = {
        "Input": RangeStats(),

        "Conv1 acc math": RangeStats(),
        "Conv1 acc20": RangeStats(),
        "Conv1 output": RangeStats(),

        "Pool1": RangeStats(),

        "Conv2 partial math": RangeStats(),
        "Conv2 partial20": RangeStats(),
        "Conv2 full math": RangeStats(),
        "Conv2 acc20": RangeStats(),
        "Conv2 internal14": RangeStats(),
        "Conv2 output": RangeStats(),

        "Pool2": RangeStats(),

        "FC input": RangeStats(),
        "FC acc math": RangeStats(),
        "FC acc20": RangeStats(),
        "FC logits": RangeStats(),
    }

    num_images = len(images)

    for idx, image in enumerate(images):

        _, trace = model.forward(
            image,
            return_trace=True,
        )

        collectors[
            "Input"
        ].update(
            trace.input_image
        )

        collectors[
            "Conv1 acc math"
        ].update(
            trace.conv1_acc_math
        )

        collectors[
            "Conv1 acc20"
        ].update(
            trace.conv1_acc20
        )

        collectors[
            "Conv1 output"
        ].update(
            trace.conv1_out
        )

        collectors[
            "Pool1"
        ].update(
            trace.pool1
        )

        collectors[
            "Conv2 partial math"
        ].update(
            trace.conv2_partial_math
        )

        collectors[
            "Conv2 partial20"
        ].update(
            trace.conv2_partial20
        )

        collectors[
            "Conv2 full math"
        ].update(
            trace.conv2_full_math
        )

        collectors[
            "Conv2 acc20"
        ].update(
            trace.conv2_acc20
        )

        collectors[
            "Conv2 internal14"
        ].update(
            trace.conv2_internal14
        )

        collectors[
            "Conv2 output"
        ].update(
            trace.conv2_out
        )

        collectors[
            "Pool2"
        ].update(
            trace.pool2
        )

        collectors[
            "FC input"
        ].update(
            trace.fc_input
        )

        collectors[
            "FC acc math"
        ].update(
            trace.fc_acc_math
        )

        collectors[
            "FC acc20"
        ].update(
            trace.fc_acc20
        )

        collectors[
            "FC logits"
        ].update(
            trace.logits
        )

        if (
            (idx + 1) % 100 == 0
            or idx + 1 == num_images
        ):
            print(
                f"\rAnalyzed "
                f"{idx + 1:4d}/{num_images}",
                end="",
                flush=True,
            )

    print()

    # (declared RTL bits, signed)
    metadata = {
        "Input": (8, False),

        # mathematical pre-wrap values
        "Conv1 acc math": (
            None,
            True,
        ),

        "Conv1 acc20": (
            20,
            True,
        ),

        "Conv1 output": (
            12,
            True,
        ),

        # ReLU guarantees non-negative values.
        "Pool1": (
            12,
            False,
        ),

        "Conv2 partial math": (
            None,
            True,
        ),

        "Conv2 partial20": (
            20,
            True,
        ),

        "Conv2 full math": (
            None,
            True,
        ),

        "Conv2 acc20": (
            20,
            True,
        ),

        "Conv2 internal14": (
            14,
            True,
        ),

        "Conv2 output": (
            12,
            True,
        ),

        "Pool2": (
            12,
            False,
        ),

        # fc.v sign-extends the 12-bit inputs to 14 bits.
        "FC input": (
            14,
            True,
        ),

        "FC acc math": (
            None,
            True,
        ),

        "FC acc20": (
            20,
            True,
        ),

        "FC logits": (
            12,
            True,
        ),
    }

    rows = []

    for name, stats in collectors.items():

        declared_bits, signed = metadata[
            name
        ]

        rows.append(
            make_row(
                name=name,
                stats=stats,
                declared_bits=declared_bits,
                signed=signed,
            )
        )

    return rows


def parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
    )

    parser.add_argument(
        "--limit",
        type=int,
        default=None,
    )

    return parser.parse_args()


def main():
    args = parse_args()

    params = load_parameters(
        DATA_DIR
    )

    model = RTLReferenceCNN(
        params
    )

    images = load_input_1000(
        args.dataset
    )

    if args.limit is not None:
        images = images[:args.limit]

    # ------------------------------------------------------------
    # Weight analysis
    # ------------------------------------------------------------

    weight_rows = analyze_weights(
        params
    )

    print_rows(
        "WEIGHT / BIAS RANGE ANALYSIS",
        weight_rows,
    )

    weight_csv = (
        TABLE_DIR
        / "weight_stats.csv"
    )

    save_csv(
        weight_csv,
        weight_rows,
    )

    # ------------------------------------------------------------
    # Activation analysis
    # ------------------------------------------------------------

    activation_rows = (
        analyze_activations(
            model,
            images,
        )
    )

    print_rows(
        "ACTIVATION / ACCUMULATOR RANGE ANALYSIS",
        activation_rows,
    )

    activation_csv = (
        TABLE_DIR
        / "activation_stats.csv"
    )

    save_csv(
        activation_csv,
        activation_rows,
    )

    print()
    print(f"Saved: {weight_csv}")
    print(f"Saved: {activation_csv}")


if __name__ == "__main__":
    main()