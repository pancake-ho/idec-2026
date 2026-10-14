"""Local SSIM teacher: 11x11 Gaussian, sigma1.5, valid, population moments."""
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from ..spec import SSIM_THRESHOLDS

def grade(score):
    s = float(score)
    if not np.isfinite(s) or not -1 <= s <= 1:
        raise ValueError('finite SSIM in [-1,1] required')
    poor, great, excellent = SSIM_THRESHOLDS
    return 0 if s >= excellent else 1 if s >= great else 2 if s > poor else 3

def ssim_local(reference, distorted):
    a = np.asarray(reference, np.float64); b = np.asarray(distorted, np.float64)
    if a.shape != (28, 28) or b.shape != a.shape:
        raise ValueError('SSIM needs aligned 28x28 patches')
    if not np.isfinite(a).all() or not np.isfinite(b).all() or min(a.min(), b.min()) < 0 or max(a.max(), b.max()) > 255:
        raise ValueError('Y code range 0..255')
    g = np.exp(-np.arange(-5, 6, dtype=float) ** 2 / (2 * 1.5 ** 2)); g /= g.sum()
    window = g[:, None] * g[None, :]
    blur = lambda x: np.einsum('ijab,ab->ij', sliding_window_view(x, (11, 11)), window)
    ma, mb = blur(a), blur(b)
    va = np.maximum(0, blur(a * a) - ma * ma); vb = np.maximum(0, blur(b * b) - mb * mb)
    cov = blur(a * b) - ma * mb
    c1, c2 = (.01 * 255) ** 2, (.03 * 255) ** 2
    return float(np.clip((((2 * ma * mb + c1) * (2 * cov + c2)) /
                         ((ma * ma + mb * mb + c1) * (va + vb + c2))).mean(), -1, 1))
