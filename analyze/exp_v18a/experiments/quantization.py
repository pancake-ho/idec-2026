"""Exploratory power-of-two STEP quantization, not power-of-two weight pruning.

q has fewer bits; restored=q*2**shift is fed to the unchanged integer model.
No extra saturation is inserted into original Conv/FC arithmetic. Biases and
original output slices are unchanged. This is a PTQ experiment, not DDAMQ QAT.
"""
from dataclasses import replace
import numpy as np

def round_shift(x, shift, mode):
    x = np.asarray(x, dtype=np.int64)
    if shift == 0:
        return x.copy()
    if mode == "floor":
        return x >> shift
    if mode == "trunc":
        return np.sign(x) * (np.abs(x) >> shift)
    if mode == "even":
        return np.rint(x / float(1 << shift)).astype(np.int64)
    raise ValueError("rounding must be floor, trunc or even")

def weight_quant(x, bits, mode):
    if not 2 <= bits <= 8:
        raise ValueError("weight bits must be 2..8")
    shift = 8 - bits
    q = np.clip(round_shift(x, shift, mode), -(1 << (bits-1)), (1 << (bits-1))-1)
    return q * (1 << shift), q, shift

def activation_quant(x, bits, mode):
    if not 1 <= bits <= 11:
        raise ValueError("unsigned pooled activation bits must be 1..11")
    shift = 11 - bits
    q = np.clip(round_shift(x, shift, mode), 0, (1 << bits)-1)
    return q * (1 << shift)

def quant_parameters(params, bits, mode):
    names = ("conv1_w", "conv2_w", "fc_w")
    values = {n: weight_quant(getattr(params,n),int(b),mode)[0] for n,b in zip(names,bits)}
    return replace(params, **values)
