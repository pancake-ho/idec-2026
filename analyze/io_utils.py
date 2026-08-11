from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from config import (
    DATA_DIR,
    INPUT_H,
    INPUT_W,
    CONV1_KERNEL,
    CONV1_COUT,
    CONV2_KERNEL,
    CONV2_CIN,
    CONV2_COUT,
    FC_IN,
    FC_OUT,
)

from fixed_point import to_signed


@dataclass
class RTLParameters:
    # [out_channel, kernel_h, kernel_w]
    conv1_w: np.ndarray

    # [out_channel]
    conv1_b: np.ndarray

    # [out_channel, in_channel, kernel_h, kernel_w]
    conv2_w: np.ndarray

    # [out_channel]
    conv2_b: np.ndarray

    # [class, input_feature]
    fc_w: np.ndarray

    # [class]
    fc_b: np.ndarray


def _read_memh_tokens(path: Path) -> list[str]:
    """
    Read tokens from a simple $readmemh-compatible text file.

    Supports whitespace-separated hexadecimal tokens.

    The current competition data files do not require @address
    directives, X, or Z values. Those are rejected intentionally
    to avoid silently creating an incorrect Golden Model.
    """
    path = Path(path)

    if not path.exists():
        raise FileNotFoundError(path)

    tokens: list[str] = []

    with path.open(
        "r",
        encoding="utf-8",
        errors="ignore",
    ) as f:

        for line_no, line in enumerate(f, start=1):

            # Remove Verilog-style comments.
            line = line.split("//", 1)[0]

            # Also allow Python/shell-style comments in our future files.
            line = line.split("#", 1)[0]

            for token in line.split():

                token = token.strip().rstrip(",")

                if not token:
                    continue

                if token.startswith("@"):
                    raise ValueError(
                        f"{path}:{line_no}: "
                        "@address directive is not supported."
                    )

                lower = token.lower()

                if "x" in lower or "z" in lower:
                    raise ValueError(
                        f"{path}:{line_no}: "
                        f"X/Z token found: {token}"
                    )

                try:
                    int(token, 16)
                except ValueError as exc:
                    raise ValueError(
                        f"{path}:{line_no}: "
                        f"invalid hexadecimal token '{token}'"
                    ) from exc

                tokens.append(token)

    return tokens


def load_memh_unsigned(
    path: Path,
    bits: int,
) -> np.ndarray:

    tokens = _read_memh_tokens(path)

    mask = (1 << bits) - 1

    values = [
        int(token, 16) & mask
        for token in tokens
    ]

    return np.asarray(values, dtype=np.int64)


def load_memh_signed(
    path: Path,
    bits: int,
) -> np.ndarray:

    raw = load_memh_unsigned(path, bits)

    return to_signed(raw, bits)


def load_single_image(path: Path) -> np.ndarray:
    """
    Load one 28x28 unsigned 8-bit image.
    """
    values = load_memh_unsigned(path, bits=8)

    expected = INPUT_H * INPUT_W

    if values.size != expected:
        raise ValueError(
            f"{path}: expected {expected} pixels, "
            f"got {values.size}"
        )

    return values.reshape(INPUT_H, INPUT_W)


def load_input_1000(
    path: Path,
) -> np.ndarray:
    """
    Load input_1000.txt.

    top_tb_1000 declares:
        pixels[0:783999]

    so the file is expected to contain:
        1000 * 784 = 784000 pixels.
    """
    values = load_memh_unsigned(path, bits=8)

    image_size = INPUT_H * INPUT_W

    if values.size % image_size != 0:
        raise ValueError(
            f"{path}: pixel count {values.size} "
            f"is not divisible by {image_size}"
        )

    num_images = values.size // image_size

    return values.reshape(
        num_images,
        INPUT_H,
        INPUT_W,
    )


def infer_label_from_filename(path: Path) -> int:
    """
    2_0.txt -> 2
    7_0.txt -> 7
    """
    stem = Path(path).stem

    first = stem.split("_")[0]

    try:
        label = int(first)
    except ValueError as exc:
        raise ValueError(
            f"Cannot infer label from filename: {path}"
        ) from exc

    if not 0 <= label <= 9:
        raise ValueError(f"Invalid MNIST label: {label}")

    return label


def labels_for_input_1000(
    num_images: int,
) -> np.ndarray:
    """
    The provided top_tb_1000 evaluates the image selected by rand_num
    against:

        rand_num % 10

    Therefore the supplied input_1000 dataset is interpreted as:
        image 0 -> class 0
        image 1 -> class 1
        ...
        image 9 -> class 9
        image 10 -> class 0
        ...
    """
    return (
        np.arange(num_images, dtype=np.int64) % 10
    )


def load_parameters(
    data_dir: Path = DATA_DIR,
) -> RTLParameters:

    data_dir = Path(data_dir)

    # ------------------------------------------------------------
    # Conv1
    # ------------------------------------------------------------

    conv1_files = [
        "conv1_weight_1.txt",
        "conv1_weight_2.txt",
        "conv1_weight_3.txt",
    ]

    conv1_weights = []

    for filename in conv1_files:

        values = load_memh_signed(
            data_dir / filename,
            bits=8,
        )

        if values.size != CONV1_KERNEL * CONV1_KERNEL:
            raise ValueError(
                f"{filename}: expected 25 weights, "
                f"got {values.size}"
            )

        conv1_weights.append(
            values.reshape(
                CONV1_KERNEL,
                CONV1_KERNEL,
            )
        )

    conv1_w = np.stack(conv1_weights, axis=0)

    if conv1_w.shape != (
        CONV1_COUT,
        CONV1_KERNEL,
        CONV1_KERNEL,
    ):
        raise AssertionError(conv1_w.shape)

    conv1_b = load_memh_signed(
        data_dir / "conv1_bias.txt",
        bits=8,
    )

    if conv1_b.size != CONV1_COUT:
        raise ValueError(
            f"conv1_bias.txt: expected {CONV1_COUT}, "
            f"got {conv1_b.size}"
        )

    # ------------------------------------------------------------
    # Conv2
    #
    # RTL mapping:
    #
    # output channel 0:
    #   w_211, w_212, w_213
    #
    # output channel 1:
    #   w_221, w_222, w_223
    #
    # output channel 2:
    #   w_231, w_232, w_233
    # ------------------------------------------------------------

    conv2_names = [
        [
            "conv2_weight_11.txt",
            "conv2_weight_12.txt",
            "conv2_weight_13.txt",
        ],
        [
            "conv2_weight_21.txt",
            "conv2_weight_22.txt",
            "conv2_weight_23.txt",
        ],
        [
            "conv2_weight_31.txt",
            "conv2_weight_32.txt",
            "conv2_weight_33.txt",
        ],
    ]

    conv2_w = np.zeros(
        (
            CONV2_COUT,
            CONV2_CIN,
            CONV2_KERNEL,
            CONV2_KERNEL,
        ),
        dtype=np.int64,
    )

    for out_ch in range(CONV2_COUT):
        for in_ch in range(CONV2_CIN):

            filename = conv2_names[out_ch][in_ch]

            values = load_memh_signed(
                data_dir / filename,
                bits=8,
            )

            expected = CONV2_KERNEL * CONV2_KERNEL

            if values.size != expected:
                raise ValueError(
                    f"{filename}: expected {expected}, "
                    f"got {values.size}"
                )

            conv2_w[out_ch, in_ch] = values.reshape(
                CONV2_KERNEL,
                CONV2_KERNEL,
            )

    conv2_b = load_memh_signed(
        data_dir / "conv2_bias.txt",
        bits=8,
    )

    if conv2_b.size != CONV2_COUT:
        raise ValueError(
            f"conv2_bias.txt: expected {CONV2_COUT}, "
            f"got {conv2_b.size}"
        )

    # ------------------------------------------------------------
    # Fully connected
    # ------------------------------------------------------------

    fc_values = load_memh_signed(
        data_dir / "fc_weight.txt",
        bits=8,
    )

    if fc_values.size != FC_OUT * FC_IN:
        raise ValueError(
            f"fc_weight.txt: expected "
            f"{FC_OUT * FC_IN} weights, "
            f"got {fc_values.size}"
        )

    # RTL:
    # weight[out_idx * INPUT_NUM + feature]
    fc_w = fc_values.reshape(FC_OUT, FC_IN)

    fc_b = load_memh_signed(
        data_dir / "fc_bias.txt",
        bits=8,
    )

    if fc_b.size != FC_OUT:
        raise ValueError(
            f"fc_bias.txt: expected {FC_OUT}, "
            f"got {fc_b.size}"
        )

    return RTLParameters(
        conv1_w=conv1_w,
        conv1_b=conv1_b,
        conv2_w=conv2_w,
        conv2_b=conv2_b,
        fc_w=fc_w,
        fc_b=fc_b,
    )