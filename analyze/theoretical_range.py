from __future__ import annotations

import csv
from dataclasses import dataclass

import numpy as np

from config import DATA_DIR, TABLE_DIR
from fixed_point import required_signed_bits
from io_utils import load_parameters


# ============================================================
# Interval arithmetic
# ============================================================

@dataclass(frozen=True)
class Interval:
    lo: int
    hi: int

    def __post_init__(self):
        if self.lo > self.hi:
            raise ValueError(
                f"Invalid interval [{self.lo}, {self.hi}]"
            )

    def add(self, other: "Interval") -> "Interval":
        return Interval(
            self.lo + other.lo,
            self.hi + other.hi,
        )

    def add_scalar(self, value: int) -> "Interval":
        value = int(value)

        return Interval(
            self.lo + value,
            self.hi + value,
        )

    def relu(self) -> "Interval":
        return Interval(
            max(0, self.lo),
            max(0, self.hi),
        )


def signed_limits(bits: int) -> Interval:
    return Interval(
        -(1 << (bits - 1)),
        (1 << (bits - 1)) - 1,
    )


def fits_signed(
    interval: Interval,
    bits: int,
) -> bool:

    limits = signed_limits(bits)

    return (
        interval.lo >= limits.lo
        and interval.hi <= limits.hi
    )


def assign_signed(
    interval: Interval,
    bits: int,
) -> tuple[Interval, bool]:
    """
    Model assignment into a signed `bits`-wide RTL signal.

    If the entire source interval fits, the range is preserved.

    If overflow/wrap is theoretically possible, the conservative
    result is the full signed range.
    """
    if fits_signed(interval, bits):
        return interval, True

    return signed_limits(bits), False


def multiply_interval(
    interval: Interval,
    weight: int,
) -> Interval:

    weight = int(weight)

    a = interval.lo * weight
    b = interval.hi * weight

    return Interval(
        min(a, b),
        max(a, b),
    )


def weighted_sum_bound(
    input_intervals: list[Interval],
    weights: np.ndarray,
) -> Interval:

    weights = np.asarray(
        weights,
        dtype=np.int64,
    ).reshape(-1)

    if len(input_intervals) != weights.size:
        raise ValueError(
            "Number of intervals and weights differ: "
            f"{len(input_intervals)} vs {weights.size}"
        )

    result = Interval(0, 0)

    for input_interval, weight in zip(
        input_intervals,
        weights,
    ):
        result = result.add(
            multiply_interval(
                input_interval,
                int(weight),
            )
        )

    return result


def signed_part_select_bound(
    interval: Interval,
    source_bits: int,
    msb: int,
    lsb: int,
) -> tuple[Interval, bool]:
    """
    Conservative bound for a Verilog signed part-select.

    Exact/simple case:
        selected field includes original sign bit,
        i.e. msb == source_bits - 1.

    Then x[source_bits-1:lsb], interpreted signed,
    is equivalent to arithmetic right shift by lsb
    as long as the source itself does not overflow.

    Non-top slices such as FC calc_out[18:7] from a
    20-bit source omit the original sign bit. For those,
    report the complete output range conservatively.
    """
    width = msb - lsb + 1

    if not fits_signed(interval, source_bits):
        return signed_limits(width), False

    if msb != source_bits - 1:
        return signed_limits(width), False

    scale = 1 << lsb

    return Interval(
        interval.lo // scale,
        interval.hi // scale,
    ), True


# ============================================================
# Report helper
# ============================================================

ROWS: list[dict] = []


def add_row(
    name: str,
    interval: Interval,
    declared_bits: int | None,
    proven_no_wrap: bool,
    note: str = "",
):
    need = required_signed_bits(
        interval.lo,
        interval.hi,
    )

    ROWS.append(
        {
            "tensor": name,
            "declared_bits": (
                ""
                if declared_bits is None
                else declared_bits
            ),
            "required_bits_for_bound": need,
            "min": interval.lo,
            "max": interval.hi,
            "proven_no_wrap": int(proven_no_wrap),
            "note": note,
        }
    )


# ============================================================
# Conv1
# ============================================================

def analyze_conv1(params):
    input_interval = Interval(0, 255)

    pool1_intervals: list[Interval] = []

    for oc in range(3):

        weights = params.conv1_w[oc].reshape(-1)

        acc_raw = weighted_sum_bound(
            [input_interval] * 25,
            weights,
        )

        acc20, acc_safe = assign_signed(
            acc_raw,
            20,
        )

        add_row(
            f"Conv1 ch{oc} accumulator raw",
            acc_raw,
            20,
            acc_safe,
            "All possible uint8 5x5 input patches",
        )

        sliced, slice_safe = (
            signed_part_select_bound(
                acc20,
                source_bits=20,
                msb=19,
                lsb=8,
            )
        )

        out_raw = sliced.add_scalar(
            int(params.conv1_b[oc])
        )

        out12, out_safe = assign_signed(
            out_raw,
            12,
        )

        add_row(
            f"Conv1 ch{oc} output",
            out12,
            12,
            acc_safe and slice_safe and out_safe,
            "calc_out[19:8] + bias",
        )

        pool = out12.relu()

        add_row(
            f"Pool1 ch{oc}",
            pool,
            12,
            acc_safe and slice_safe and out_safe,
            "2x2 max cannot exceed Conv1 channel bound; ReLU",
        )

        pool1_intervals.append(pool)

    return pool1_intervals


# ============================================================
# Conv2
# ============================================================

def analyze_conv2(
    params,
    pool1_intervals: list[Interval],
):
    pool2_intervals: list[Interval] = []

    for oc in range(3):

        partial20_list: list[Interval] = []
        all_partial_safe = True

        for ic in range(3):

            weights = params.conv2_w[
                oc,
                ic,
            ].reshape(-1)

            partial_raw = weighted_sum_bound(
                [pool1_intervals[ic]] * 25,
                weights,
            )

            partial20, safe = assign_signed(
                partial_raw,
                20,
            )

            all_partial_safe &= safe

            add_row(
                f"Conv2 out{oc}/in{ic} partial",
                partial_raw,
                20,
                safe,
                "25-MAC theoretical bound",
            )

            partial20_list.append(
                partial20
            )

        acc_raw = Interval(0, 0)

        for partial in partial20_list:
            acc_raw = acc_raw.add(
                partial
            )

        acc20, acc_safe = assign_signed(
            acc_raw,
            20,
        )

        add_row(
            f"Conv2 out{oc} accumulator",
            acc_raw,
            20,
            all_partial_safe and acc_safe,
            "Sum of three signed 20-bit partial results",
        )

        internal14, slice1_safe = (
            signed_part_select_bound(
                acc20,
                source_bits=20,
                msb=19,
                lsb=6,
            )
        )

        internal14, internal_safe = assign_signed(
            internal14,
            14,
        )

        add_row(
            f"Conv2 out{oc} internal14",
            internal14,
            14,
            (
                all_partial_safe
                and acc_safe
                and slice1_safe
                and internal_safe
            ),
            "calc_out[19:6]",
        )

        pre_bias, slice2_safe = (
            signed_part_select_bound(
                internal14,
                source_bits=14,
                msb=13,
                lsb=1,
            )
        )

        out_raw = pre_bias.add_scalar(
            int(params.conv2_b[oc])
        )

        out12, out_safe = assign_signed(
            out_raw,
            12,
        )

        safe_total = (
            all_partial_safe
            and acc_safe
            and slice1_safe
            and internal_safe
            and slice2_safe
            and out_safe
        )

        add_row(
            f"Conv2 out{oc} output",
            out12,
            12,
            safe_total,
            "conv_out[13:1] + bias",
        )

        pool = out12.relu()

        add_row(
            f"Pool2 ch{oc}",
            pool,
            12,
            safe_total,
            "2x2 max + ReLU",
        )

        pool2_intervals.append(pool)

    return pool2_intervals


# ============================================================
# Fully Connected
# ============================================================

def analyze_fc(
    params,
    pool2_intervals: list[Interval],
):
    # fc.v layout:
    #
    # buffer[ 0:15] = channel 0
    # buffer[16:31] = channel 1
    # buffer[32:47] = channel 2

    input_intervals = (
        [pool2_intervals[0]] * 16
        + [pool2_intervals[1]] * 16
        + [pool2_intervals[2]] * 16
    )

    for cls in range(10):

        raw = weighted_sum_bound(
            input_intervals,
            params.fc_w[cls],
        )

        raw = raw.add_scalar(
            int(params.fc_b[cls])
        )

        acc20, acc_safe = assign_signed(
            raw,
            20,
        )

        add_row(
            f"FC class{cls} accumulator",
            raw,
            20,
            acc_safe,
            "48-MAC + bias",
        )

        # IMPORTANT:
        #
        # RTL uses calc_out[18:7].
        # Bit 19 is NOT part of the selected field.
        #
        # Therefore a simple arithmetic-shift interval is not
        # generally exact. Conservatively report full 12-bit range.
        logits, slice_safe = (
            signed_part_select_bound(
                acc20,
                source_bits=20,
                msb=18,
                lsb=7,
            )
        )

        add_row(
            f"FC class{cls} logit",
            logits,
            12,
            acc_safe and slice_safe,
            (
                "calc_out[18:7]; non-top part-select, "
                "full 12-bit range reported conservatively"
            ),
        )


# ============================================================
# FC 14 -> 12 proof
# ============================================================

def print_fc_width_proof():
    print()
    print("=" * 88)
    print("FC BUFFER WIDTH CHECK")
    print("=" * 88)

    print(
        "FC input ports are signed [11:0]. "
        "The current RTL only sign-extends them to 14 bits before storage."
    )

    print(
        "Therefore storing the same signed [11:0] value directly in a "
        "12-bit signed buffer preserves the numeric value for every "
        "possible input bit pattern."
    )

    a = Interval(-2048, 2047)
    b = Interval(-128, 127)

    candidates = [
        a.lo * b.lo,
        a.lo * b.hi,
        a.hi * b.lo,
        a.hi * b.hi,
    ]

    product_interval = Interval(
        min(candidates),
        max(candidates),
    )

    bits = required_signed_bits(
        product_interval.lo,
        product_interval.hi,
    )

    print(
        f"Exact signed12 x signed8 product range: "
        f"[{product_interval.lo}, {product_interval.hi}]"
    )

    print(
        f"Required full product width: {bits} bits"
    )

    print(
        "=> 20-bit product is sufficient for all possible signed12 x signed8 inputs."
    )

    print("=" * 88)


def main():
    params = load_parameters(
        DATA_DIR
    )

    pool1 = analyze_conv1(
        params
    )

    pool2 = analyze_conv2(
        params,
        pool1,
    )

    analyze_fc(
        params,
        pool2,
    )

    output_path = (
        TABLE_DIR
        / "theoretical_range.csv"
    )

    with output_path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:

        writer = csv.DictWriter(
            f,
            fieldnames=list(
                ROWS[0].keys()
            ),
        )

        writer.writeheader()
        writer.writerows(ROWS)

    print()
    print("=" * 120)
    print("THEORETICAL RANGE ANALYSIS")
    print("=" * 120)

    print(
        f"{'Tensor':<36}"
        f"{'RTL':>7}"
        f"{'Need':>7}"
        f"{'Min':>14}"
        f"{'Max':>14}"
        f"{'Safe':>8}"
    )

    print("-" * 120)

    for row in ROWS:

        print(
            f"{row['tensor']:<36}"
            f"{str(row['declared_bits']):>7}"
            f"{str(row['required_bits_for_bound']):>7}"
            f"{int(row['min']):>14}"
            f"{int(row['max']):>14}"
            f"{('YES' if row['proven_no_wrap'] else 'NO'):>8}"
        )

    print("=" * 120)

    print_fc_width_proof()

    print()
    print(f"Saved: {output_path}")


if __name__ == "__main__":
    main()