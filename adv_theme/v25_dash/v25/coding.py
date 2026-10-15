"""Deterministic zero/signed-PoT and two-term SP2 codebooks."""
from functools import lru_cache
import numpy as np

@lru_cache(maxsize=32)
def table(bits, scheme):
    if not 2 <= int(bits) <= 16 or scheme not in ('pot1','sp2'):
        raise ValueError('supported signed coefficient codebook required')
    powers = [1 << e for e in range(bits)]
    entries = {0: ()}
    for p in powers:
        entries[p]=(p,); entries[-p]=(-p,)
    if scheme == 'sp2':
        for i,p in enumerate(powers):
            for q in powers[:i]:
                for a in (-p,p):
                    for b in (-q,q):
                        v=a+b
                        if v not in entries or len(entries[v])>2: entries[v]=(a,b)
    lo,hi=-(1<<(bits-1)),(1<<(bits-1))-1
    # First minimum implements the V25 per-lane tie rule: fewer terms, smaller magnitude.
    keys=sorted((v for v in entries if lo<=v<=hi),key=lambda v:(len(entries[v]),abs(v),v))
    terms=np.zeros((len(keys),2),np.int64)
    for i,v in enumerate(keys):terms[i,:len(entries[v])]=entries[v]
    return np.array(keys,np.int64),terms

def quantize(values,bits,scheme):
    x=np.asarray(values,np.int64); out=np.empty_like(x); terms=np.zeros(x.shape+(2,),np.int64)
    if np.ndim(bits)==0:
        vs,ts=table(int(bits),scheme); ix=np.abs(x[...,None]-vs).argmin(-1)
        return vs[ix],ts[ix]
    bs=np.asarray(bits,np.int64)
    if bs.shape!=(x.shape[-1],):raise ValueError('one bit width per lane')
    for lane,b in enumerate(bs):
        vs,ts=table(int(b),scheme); ix=np.abs(x[...,lane,None]-vs).argmin(-1)
        out[...,lane]=vs[ix];terms[...,lane,:]=ts[ix]
    return out,terms

def single_terms(coefficients):
    x=np.asarray(coefficients,np.int64)
    a=np.abs(x)
    if np.any((a!=0)&((a&(a-1))!=0)):raise ValueError('non-PoT coefficient')
    return x

def shift_products(x, coefficient):
    c=single_terms(coefficient);a=np.abs(c)
    exps=np.zeros_like(c)
    for v in np.unique(a):
        if v:exps[a==v]=int(v).bit_length()-1
    shifted=np.left_shift(np.asarray(x,np.int64),exps)
    return np.where(c>0,shifted,np.where(c<0,-shifted,0))
