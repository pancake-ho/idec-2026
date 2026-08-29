#!/usr/bin/env python3
"""Reference-check the V20 fixed-row Booth reduction for BW 5..9."""

from __future__ import annotations

import random


def wrap_unsigned(value: int, bits: int) -> int:
    return value & ((1 << bits) - 1)


def wrap_signed(value: int, bits: int) -> int:
    value = wrap_unsigned(value, bits)
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def booth(a: int, b: int, aw: int, bw: int) -> int:
    ng = (bw + 1) // 2
    accw = aw + bw + 2
    b_unsigned = wrap_unsigned(b, bw)

    def ybit(index: int) -> int:
        if index == 0:
            return 0
        original = index - 1
        if original < bw:
            return (b_unsigned >> original) & 1
        return (b_unsigned >> (bw - 1)) & 1

    rows = [0] * 5
    correction = 0
    a_ext = wrap_signed(a, accw)
    for group in range(ng):
        code = sum(ybit(2 * group + bit) << bit for bit in range(3))
        one = code in (0b001, 0b010, 0b101, 0b110)
        two = code in (0b011, 0b100)
        negative = code in (0b100, 0b101, 0b110)
        magnitude = a_ext if one else (a_ext << 1 if two else 0)
        if negative:
            inverted = wrap_unsigned(~wrap_unsigned(magnitude, accw), accw)
            rows[group] = wrap_signed(inverted << (2 * group), accw)
            correction |= 1 << (2 * group)
        else:
            rows[group] = wrap_signed(magnitude << (2 * group), accw)
    total = wrap_signed(sum(rows) + correction, accw)
    return wrap_signed(total, aw + bw)


def main() -> None:
    rng = random.Random(20260829)
    cases = 0
    for aw in (12, 13, 14):
        a_values = {
            -(1 << (aw - 1)),
            -(1 << (aw - 1)) + 1,
            -2,
            -1,
            0,
            1,
            2,
            (1 << (aw - 1)) - 2,
            (1 << (aw - 1)) - 1,
        }
        a_values.update(rng.randrange(-(1 << (aw - 1)), 1 << (aw - 1)) for _ in range(256))
        for bw in range(5, 10):
            for a in a_values:
                for b in range(-(1 << (bw - 1)), 1 << (bw - 1)):
                    actual = booth(a, b, aw, bw)
                    expected = wrap_signed(a * b, aw + bw)
                    if actual != expected:
                        raise SystemExit(
                            f"FAIL AW={aw} BW={bw} a={a} b={b}: "
                            f"actual={actual}, expected={expected}"
                        )
                    cases += 1
    print(f"Booth reference checks: PASS ({cases} operand pairs)")


if __name__ == "__main__":
    main()
