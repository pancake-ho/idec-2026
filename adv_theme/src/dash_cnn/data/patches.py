"""Deterministic local patches and observable controls; reference never enters CNN input."""
import numpy as np

def coordinates(height, width, grid):
    if min(height, width) < 28:
        raise ValueError('frame smaller than patch')
    result = [(int(round((height - 28) * yy)), int(round((width - 28) * xx))) for yy, xx in grid]
    if len(set(result)) != len(result) or any(y < 0 or x < 0 or y + 28 > height or x + 28 > width for y, x in result):
        raise ValueError('duplicate or out-of-range patch coordinates')
    return result

def controls(x, bitrate, width, height, fps):
    a = x.astype(float) / 255
    meta = np.array([np.log2(max(bitrate / (width * height * fps), 1e-9)), np.log2(width), np.log2(height)])
    spatial = np.array([a.mean(), a.std(), np.abs(np.diff(a, axis=0)).mean(), np.abs(np.diff(a, axis=1)).mean(),
                        (np.diff(a, 2, axis=0) ** 2).mean(), (np.diff(a, 2, axis=1) ** 2).mean()])
    return meta, np.r_[meta, spatial]
