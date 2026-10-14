"""One authoritative class and integer model contract (AVC shared, four classes)."""
import numpy as np

NUM_CLASSES = 4
PATCH_SIZE = 28
CLASSES = ('excellent', 'great', 'good', 'poor')
SSIM_THRESHOLDS = (0.80, 0.90, 0.95)
COORDS = [(r, c) for r in range(5) for c in range(5) if r < 3 or c < 3]
VARIANTS = {
    'dense8': dict(mask=False, side_bits=8, fc_bits=8, a1_bits=11, a2_bits=11),
    'mask8': dict(mask=True, side_bits=8, fc_bits=8, a1_bits=11, a2_bits=11),
    'mixed11': dict(mask=True, side_bits=6, fc_bits=6, a1_bits=11, a2_bits=11),
    'final': dict(mask=True, side_bits=6, fc_bits=6, a1_bits=8, a2_bits=11),
}

def code_layout(v):
    bits = np.full((5, 5), v['side_bits']); bits[:3, :3] = 8
    delta = np.full((5, 5), 8 - v['side_bits']); delta[:3, :3] = 0
    lo = -(2. ** (bits - 1)); hi = 2. ** (bits - 1) - 1
    if v['mask']:
        lo[3:, 3:] = 0; hi[3:, 3:] = 0
    return lo, hi, delta

def counts():
    tiles = 2016; fc = NUM_CLASSES * 192
    return dict(conv_tile_requests=tiles, fc40_requests=NUM_CLASSES * 5,
                direct_sparse_products=tiles * 84 + fc,
                dwm40_products=tiles * 40 + fc,
                active_weights=6 * 21 + 12 * 6 * 21 + fc,
                classes=NUM_CLASSES, codec_banks=1)
