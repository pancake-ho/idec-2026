"""Functional integer model of V18A P0..P6. Not a scheduler/cycle model.

Every physical register width, the FC 19-bit product slice and block shifts
are modeled. Valid/tag timing remains a separate RTL test obligation.
"""
from __future__ import annotations
import numpy as np
from exp_v18a.io.common import wrap_signed, required_signed_bits

AW = np.full(49, 13, dtype=int)
AW[5] = 14
AW[[17, 23, 26, 32, 34, 35, 41, 43, 44, 45, 47]] = 12
BW = np.full(49, 8, dtype=int)
BW[[16,18,25,27,28,31,36,39,41,43,45,47]] = 9
BW[[0,3,12,15,17,19,21,22,24,26,29,30,32,35,37,38,44]] = 10
BW[[1,2,4,7,8,11,13,14,20,23,33,34]] = 11
BW[[5,6,9,10]] = 12
PW = np.array([22,23,23,22,23,25,24,23,23,24,24,23,22,23,23,22,
               21,21,21,22,23,22,22,22,22,21,21,21,21,22,22,21,
               21,23,22,21,21,22,22,21,20,20,20,20,21,20,20,20,20])

B3 = np.array([[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]], dtype=np.int64)
B2 = np.array([[1,-1,0],[0,1,0],[0,-1,1]], dtype=np.int64)
G3 = np.array([[2,0,0],[1,1,1],[1,-1,1],[0,0,2]], dtype=np.int64)
G2 = np.array([[1,0],[1,1],[0,1]], dtype=np.int64)
A3 = np.array([[1,1,1,0],[0,1,-1,-1]], dtype=np.int64)
A2 = np.array([[1,1,0],[0,1,1]], dtype=np.int64)
BLOCKS = [(0,3,3,0,0,16),(16,3,2,0,3,12),(28,2,3,3,0,12),(40,2,2,3,3,9)]

def widths_wrap(a, widths):
    a = np.asarray(a, dtype=np.int64)
    return np.stack([wrap_signed(a[..., i], int(w)) for i,w in enumerate(widths)], axis=-1)

def check_range(a, low, high, name):
    if np.any((a < low) | (a > high)):
        raise ValueError(f"{name} outside legal V18A range [{low},{high}]")

def conv(tile, kernel, stages=False):
    tile, kernel = np.asarray(tile, dtype=np.int64), np.asarray(kernel, dtype=np.int64)
    if tile.shape[-2:] != (6,6) or kernel.shape[-2:] != (5,5):
        raise ValueError("conv requires [...,6,6] tile and [...,5,5] kernel")
    check_range(tile,0,2047,"pooled/raw input")
    check_range(kernel,-128,127,"kernel")
    batch = np.broadcast_shapes(tile.shape[:-2], kernel.shape[:-2])
    tile = np.broadcast_to(tile, batch+(6,6))
    kernel = np.broadcast_to(kernel, batch+(5,5))
    p1a, p1b, p2a, p2b, p3, p4, p5 = [], [], [], [], [], [], []
    for offset,r,c,rr,cc,n in BLOCKS:
        br,bc = (B3 if r==3 else B2),(B3 if c==3 else B2)
        gr,gc = (G3 if r==3 else G2),(G3 if c==3 else G2)
        ar,ac = (A3 if r==3 else A2),(A3 if c==3 else A2)
        x = tile[...,rr:rr+r+1,cc:cc+c+1]
        w = kernel[...,rr:rr+r,cc:cc+c]
        ha = wrap_signed(x @ bc.T,13)
        hb = wrap_signed(w @ gc.T,10)
        va0,vb0 = br @ ha, gr @ hb
        va = widths_wrap(va0.reshape(batch+(n,)),AW[offset:offset+n]).reshape(batch+(r+1,c+1))
        vb = widths_wrap(vb0.reshape(batch+(n,)),BW[offset:offset+n]).reshape(batch+(r+1,c+1))
        prod = widths_wrap((va*vb).reshape(batch+(n,)),PW[offset:offset+n]).reshape(batch+(r+1,c+1))
        # a2_h/a3_h return signed26 before narrower physical P4 assignment.
        h = wrap_signed(wrap_signed(prod @ ac.T,26), {(3,3):26,(3,2):24,(2,3):24,(2,2):22}[r,c])
        # a2_v/a3_v return signed27 before narrower physical P5 assignment.
        v = wrap_signed(wrap_signed(ar @ h,27), {(3,3):27,(3,2):25,(2,3):25,(2,2):23}[r,c])
        p1a.append(ha.reshape(batch+(-1,)))
        p1b.append(hb.reshape(batch+(-1,)))
        p2a.append(va.reshape(batch+(n,)))
        p2b.append(vb.reshape(batch+(n,)))
        p3.append(prod.reshape(batch+(n,)))
        p4.append(h.reshape(batch+(-1,)))
        p5.append(v.reshape(batch+(4,)))
    p5all = np.concatenate(p5,axis=-1)
    raw = wrap_signed((p5[0] >> 2)+(p5[1] >> 1)+(p5[2] >> 1)+p5[3],29)
    raw = wrap_signed(raw,32)
    if not stages:
        return raw
    return raw, dict(P1a=np.concatenate(p1a,axis=-1),P1b=np.concatenate(p1b,axis=-1),
                     P2a=np.concatenate(p2a,axis=-1),P2b=np.concatenate(p2b,axis=-1),
                     P3=np.concatenate(p3,axis=-1),P4=np.concatenate(p4,axis=-1),P5=p5all,P6=raw)

def fc(a,b,stages=False):
    a,b = np.broadcast_arrays(np.asarray(a,dtype=np.int64),np.asarray(b,dtype=np.int64))
    if a.shape[-1] != 48:
        raise ValueError("FC requires [...,48] operands")
    check_range(a,0,2047,"FC pooled activation")
    check_range(b,-128,127,"FC weight")
    va = widths_wrap(a,AW[:48])
    vb = widths_wrap(b,BW[:48])
    p3 = widths_wrap(va*vb,PW[:48])
    p4 = wrap_signed(wrap_signed(p3,19).reshape(a.shape[:-1]+(16,3)).sum(axis=-1),21)
    p5 = wrap_signed(p4.reshape(a.shape[:-1]+(4,4)).sum(axis=-1),23)
    raw = wrap_signed(p5.sum(axis=-1),25)
    if not stages:
        return raw
    return raw,dict(P2a=va,P2b=vb,P3=p3,P4=p4,P5=p5,P6=raw[...,None])

def direct_conv(tile,kernel):
    tile,kernel = np.asarray(tile),np.asarray(kernel)
    return np.stack([np.sum(tile[...,r:r+5,c:c+5]*kernel,axis=(-2,-1))
                     for r,c in ((0,0),(0,1),(1,0),(1,1))],axis=-1)

