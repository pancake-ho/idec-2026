from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np

from config import (
    DATA_DIR,
    DEFAULT_SINGLE_IMAGE,
    DEFAULT_DATASET,
    TABLE_DIR,
)

from fixed_point import signed_hex

from io_utils import (
    load_parameters,
    load_single_image,
    load_input_1000,
    infer_label_from_filename,
    labels_for_input_1000,
)

from rtl_model import RTLReferenceCNN


def print_range(
    name: str,
    array: np.ndarray,
):
    array = np.asarray(array)

    print(
        f"{name:<22} "
        f"shape={str(array.shape):<16} "
        f"min={int(array.min()):>8} "
        f"max={int(array.max()):>8}"
    )


def run_single(
    model: RTLReferenceCNN,
    image_path: Path,
    expected: int | None,
):
    image_path = Path(image_path)

    image = load_single_image(
        image_path
    )

    if expected is None:
        expected = infer_label_from_filename(
            image_path
        )

    pred, trace = model.forward(
        image,
        return_trace=True,
    )

    print()
    print("=" * 72)
    print("RTL FIXED-POINT GOLDEN MODEL: SINGLE IMAGE")
    print("=" * 72)

    print(f"Image file       : {image_path}")
    print(f"Expected class   : {expected}")
    print(f"Predicted class  : {pred}")
    print(
        f"Result           : "
        f"{'PASS' if pred == expected else 'FAIL'}"
    )

    print()
    print("-" * 72)
    print("Tensor shapes / ranges")
    print("-" * 72)

    print_range(
        "Input",
        trace.input_image,
    )

    print_range(
        "Conv1 acc math",
        trace.conv1_acc_math,
    )

    print_range(
        "Conv1 acc20",
        trace.conv1_acc20,
    )

    print_range(
        "Conv1 output",
        trace.conv1_out,
    )

    print_range(
        "Pool1",
        trace.pool1,
    )

    print_range(
        "Conv2 partial math",
        trace.conv2_partial_math,
    )

    print_range(
        "Conv2 partial20",
        trace.conv2_partial20,
    )

    print_range(
        "Conv2 full math",
        trace.conv2_full_math,
    )

    print_range(
        "Conv2 acc20",
        trace.conv2_acc20,
    )

    print_range(
        "Conv2 internal14",
        trace.conv2_internal14,
    )

    print_range(
        "Conv2 output",
        trace.conv2_out,
    )

    print_range(
        "Pool2",
        trace.pool2,
    )

    print_range(
        "FC input",
        trace.fc_input,
    )

    print_range(
        "FC acc math",
        trace.fc_acc_math,
    )

    print_range(
        "FC acc20",
        trace.fc_acc20,
    )

    print_range(
        "FC logits",
        trace.logits,
    )

    print()
    print("-" * 72)
    print("FC logits")
    print("-" * 72)

    for cls, value in enumerate(
        trace.logits.tolist()
    ):
        print(
            f"class {cls}: "
            f"{int(value):>6} "
            f"(12'h{signed_hex(int(value), 12)})"
        )

    print("=" * 72)


def run_dataset(
    model: RTLReferenceCNN,
    dataset_path: Path,
    limit: int | None,
    show_mismatches: int,
):
    dataset_path = Path(dataset_path)

    images = load_input_1000(
        dataset_path
    )

    if limit is not None:
        images = images[:limit]

    num_images = len(images)

    labels = labels_for_input_1000(
        num_images
    )

    predictions = np.zeros(
        num_images,
        dtype=np.int64,
    )

    print()
    print("=" * 72)
    print("RTL FIXED-POINT GOLDEN MODEL: DATASET")
    print("=" * 72)

    print(f"Dataset          : {dataset_path}")
    print(f"Images           : {num_images}")

    for idx, image in enumerate(images):

        predictions[idx] = model.forward(
            image,
            return_trace=False,
        )

        if (
            (idx + 1) % 100 == 0
            or idx + 1 == num_images
        ):
            print(
                f"\rProcessed "
                f"{idx + 1:4d}/{num_images}",
                end="",
                flush=True,
            )

    print()

    correct = predictions == labels

    hits = int(
        np.count_nonzero(correct)
    )

    accuracy = (
        100.0 * hits / num_images
    )

    print()
    print(f"Correct          : {hits}/{num_images}")
    print(f"Accuracy         : {accuracy:.3f}%")

    if num_images == 1000:
        # top_tb prints integer division accuracy/10.
        vivado_style = hits // 10

        print(
            f"Vivado-style     : {vivado_style}% "
            "(integer display)"
        )

    mismatch_indices = np.where(
        ~correct
    )[0]

    print(
        f"Mismatches       : "
        f"{len(mismatch_indices)}"
    )

    if len(mismatch_indices) > 0:

        print()
        print(
            f"First "
            f"{min(show_mismatches, len(mismatch_indices))} "
            f"mismatches:"
        )

        for idx in mismatch_indices[
            :show_mismatches
        ]:
            print(
                f"  image={int(idx):4d} "
                f"expected={int(labels[idx])} "
                f"pred={int(predictions[idx])}"
            )

    output_csv = (
        TABLE_DIR
        / "baseline_predictions.csv"
    )

    with output_csv.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.writer(f)

        writer.writerow(
            [
                "image_index",
                "expected",
                "predicted",
                "correct",
            ]
        )

        for idx in range(num_images):
            writer.writerow(
                [
                    idx,
                    int(labels[idx]),
                    int(predictions[idx]),
                    int(correct[idx]),
                ]
            )

    print()
    print(f"Saved predictions: {output_csv}")
    print("=" * 72)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Bit-exact functional model "
            "for the IDEC MNIST RTL."
        )
    )

    parser.add_argument(
        "--mode",
        choices=[
            "single",
            "dataset",
        ],
        default="single",
    )

    parser.add_argument(
        "--image",
        type=Path,
        default=DEFAULT_SINGLE_IMAGE,
    )

    parser.add_argument(
        "--expected",
        type=int,
        default=None,
    )

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

    parser.add_argument(
        "--show-mismatches",
        type=int,
        default=20,
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

    if args.mode == "single":

        run_single(
            model=model,
            image_path=args.image,
            expected=args.expected,
        )

    else:

        run_dataset(
            model=model,
            dataset_path=args.dataset,
            limit=args.limit,
            show_mismatches=args.show_mismatches,
        )


if __name__ == "__main__":
    main()