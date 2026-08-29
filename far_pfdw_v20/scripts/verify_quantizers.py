#!/usr/bin/env python3
"""Exhaustively verify the three W5 rounding rules over signed int8."""

from __future__ import annotations

import math


def floor5(value: int) -> int:
    return value >> 3


def trunc5(value: int) -> int:
    base = value >> 3
    return base + int(value < 0 and (value & 0b111) != 0)


def even5(value: int) -> int:
    base = value >> 3
    remainder = value & 0b111
    increment = remainder > 4 or (remainder == 4 and (base & 1) != 0)
    if base == 15 and increment:
        return 15
    return base + int(increment)


def main() -> None:
    checked = 0
    for value in range(-128, 128):
        expected_floor = math.floor(value / 8)
        expected_trunc = math.trunc(value / 8)
        expected_even = round(value / 8)
        expected_even = max(-16, min(15, expected_even))
        actual = (floor5(value), trunc5(value), even5(value))
        expected = (expected_floor, expected_trunc, expected_even)
        if actual != expected:
            raise SystemExit(
                f"ERROR: int8={value}: actual={actual}, expected={expected}"
            )
        if any(result < -16 or result > 15 for result in actual):
            raise SystemExit(f"ERROR: int8={value}: W5 range violation {actual}")
        checked += 1
    print(f"W5 quantizer checks: PASS ({checked} signed-int8 values x 3 modes)")


if __name__ == "__main__":
    main()
