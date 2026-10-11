"""The fixed v1.0 model contract. Other variants are controlled ablations."""
import numpy as np

NAME = 'DASH-AdaptCNN v1.0'
PROFILES = {0:'shared_fallback', 1:'h264_avc', 2:'h265_hevc'}
CLASSES = ['low_degradation','medium_degradation','high_degradation']
SSIM_THRESHOLDS = (0.90, 0.97)
COORDS = [(r,c) for r in range(5) for c in range(5) if r<3 or c<3]
FINAL = dict(mask=True, side_bits=6, fc_bits=6, a1_bits=8, a2_bits=11,
             rounding='nearest_even', rank=2, channels=[6,12], classes=3)
VARIANTS = {
    'dense8': dict(mask=False,side_bits=8,fc_bits=8,a1_bits=11,a2_bits=11),
    'mask8': dict(mask=True,side_bits=8,fc_bits=8,a1_bits=11,a2_bits=11),
    'mixed11': dict(mask=True,side_bits=6,fc_bits=6,a1_bits=11,a2_bits=11),
    'final': {k:FINAL[k] for k in ['mask','side_bits','fc_bits','a1_bits','a2_bits']},
}

def code_layout(v):
    bits=np.full((5,5),v['side_bits']); bits[:3,:3]=8
    delta=np.full((5,5),8-v['side_bits']);delta[:3,:3]=0
    lo=-(2.**(bits-1));hi=2.**(bits-1)-1
    if v['mask']:lo[3:,3:]=0;hi[3:,3:]=0
    return lo,hi,delta

def counts():
    n=2016; fc=576
    return dict(conv_tile_requests=n,fc48_requests=12,fc40_requests=15,
                direct_dense_products=n*100+fc,direct_sparse_products=n*84+fc,
                nominal_dwm49_products=n*49+fc,dwm40_products=n*40+fc,
                active_weights=2214,biases_single_profile=21,
                lora_parameters_per_codec=288,
                packed_single_profile_bytes=1920,packed_three_profile_bytes=4608)
