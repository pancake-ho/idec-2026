from __future__ import annotations

import numpy as np


def _as_int64(x):
    """
    Convert scalar/list/ndarray to numpy int64.
    """
    return np.asarray(x, dtype=np.int64)


def bit_mask(bits: int) -> int:
    if bits <= 0:
        raise ValueError(f"bits must be positive, got {bits}")

    return (1 << bits) - 1


def wrap_unsigned(x, bits: int):
    """
    Keep only the lowest `bits`.

    Equivalent to assigning into:
        logic [bits-1:0]
    """
    x = _as_int64(x)
    return x & bit_mask(bits)


def to_signed(x, bits: int):
    """
    Interpret the lowest `bits` of x as two's-complement signed integer.

    Example:
        0xFF in 8-bit -> -1
        0x80 in 8-bit -> -128
        0x7F in 8-bit -> 127
    """
    raw = wrap_unsigned(x, bits)

    sign_bit = 1 << (bits - 1)
    full_range = 1 << bits

    return np.where(
        raw & sign_bit,
        raw - full_range,
        raw,
    ).astype(np.int64)


def wrap_signed(x, bits: int):
    """
    Emulate assignment into a signed `bits`-wide RTL signal.

    Overflow is wrap-around, not saturation.
    """
    return to_signed(x, bits)


def part_select(
    x,
    source_bits: int,
    msb: int,
    lsb: int,
):
    """
    Emulate Verilog:
        x[msb:lsb]

    The returned value is the raw unsigned bit pattern.

    Example:
        calc_out[19:8]

    Important:
        Verilog part-select is a bit operation.
        Do not replace this blindly with Python signed >>.
    """
    if msb < lsb:
        raise ValueError(
            f"msb must be >= lsb: msb={msb}, lsb={lsb}"
        )

    if msb >= source_bits:
        raise ValueError(
            f"msb={msb} outside source width {source_bits}"
        )

    width = msb - lsb + 1

    raw = wrap_unsigned(x, source_bits)
    raw = raw >> lsb

    return raw & bit_mask(width)


def part_select_signed(
    x,
    source_bits: int,
    msb: int,
    lsb: int,
):
    """
    Take Verilog bit slice, then interpret the selected bits
    as a signed two's-complement integer.
    """
    raw = part_select(
        x=x,
        source_bits=source_bits,
        msb=msb,
        lsb=lsb,
    )

    width = msb - lsb + 1

    return to_signed(raw, width)


def signed_hex(value: int, bits: int) -> str:
    """
    Return RTL-style hex bit pattern.

    Example:
        signed_hex(-1, 12) -> 'fff'
    """
    raw = int(value) & bit_mask(bits)

    hex_digits = (bits + 3) // 4

    return f"{raw:0{hex_digits}x}"


def required_unsigned_bits(max_value: int) -> int:
    """
    Minimum unsigned bit-width required for [0, max_value].
    """
    max_value = int(max_value)

    if max_value < 0:
        raise ValueError("Unsigned range cannot have negative max.")

    if max_value == 0:
        return 1

    return max_value.bit_length()


def required_signed_bits(
    min_value: int,
    max_value: int,
) -> int:
    """
    Minimum two's-complement signed width required to represent
    [min_value, max_value].
    """
    min_value = int(min_value)
    max_value = int(max_value)

    if min_value > max_value:
        raise ValueError("min_value > max_value")

    for bits in range(1, 64):
        lower = -(1 << (bits - 1))
        upper = (1 << (bits - 1)) - 1

        if min_value >= lower and max_value <= upper:
            return bits

    raise ValueError(
        f"Range [{min_value}, {max_value}] exceeds int64 analysis."
    )