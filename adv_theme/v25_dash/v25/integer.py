"""Exact inference for the exported 2/3-channel model, with floor inverse and RNE activations."""
import json
from pathlib import Path
import numpy as np
from .spec import SHAPES,MODES,LANE_BW8,SOURCE_COMMIT
from .transforms import BM,GM,INVERSE,DIVISIONS,tiles,inverse,direct_conv
from .coding import quantize,shift_products,single_terms

def i32(x):
    x=np.asarray(x,np.int64)
    if x.size and (x.min()<-(1<<31) or x.max()>=(1<<31)):
        raise OverflowError('signed32 arithmetic contract exceeded')
    return x

def rne(x,shift):
    x=np.asarray(x,np.int64);s=int(shift)
    if not 0<=s<=31:raise ValueError('shift must be 0..31')
    if s==0:return x.copy()
    base=x>>s;rem=x-(base<<s);half=1<<(s-1)
    return base+((rem>half)|((rem==half)&((base&1)!=0)))

def mode(p):return str(np.asarray(p['mode']).item())

def validate(p):
    name=mode(p)
    if name not in MODES:raise ValueError('unknown exported mode')
    for k,shape in SHAPES.items():
        a=np.asarray(p[k])
        if a.shape!=shape or not np.issubdtype(a.dtype,np.integer):raise ValueError(k+' shape/type')
    for k in ('s1','s2'):
        a=np.asarray(p[k])
        if a.ndim or not np.issubdtype(a.dtype,np.integer) or not 0<=int(a)<=31:raise ValueError(k+' shift')
    for k,b in zip(('q1_sp','q2_sp','qfc'),MODES[name]['weight_bits']):
        if np.min(p[k])<-(1<<(b-1)) or np.max(p[k])>=(1<<(b-1)):raise ValueError(k+' coefficient range')
    if name=='int8':
        for sp,td in (('q1_sp','q1_td'),('q2_sp','q2_td')):
            expected=p[sp].reshape(p[sp].shape[:2]+(25,))@GM.T
            if not np.array_equal(expected,p[td]):raise ValueError('int8 G-transform mismatch')
        if p['fc_terms'].shape!=(4,48,1) or not np.array_equal(p['fc_terms'][...,0],p['qfc']):raise ValueError('int8 FC terms')
    else:
        for td,bits in (('q1_td',5),('q2_td',6)):
            q,_=quantize(p[td],np.array(LANE_BW8)-(8-bits),'pot1')
            if not np.array_equal(q,p[td]):raise ValueError('invalid transformed PoT codes')
        terms=np.asarray(p['fc_terms'])
        if terms.shape!=(4,48,2) or not np.issubdtype(terms.dtype,np.integer):raise ValueError('SP2 term shape/type')
        single_terms(terms)
        if not np.array_equal(terms.sum(-1),p['qfc']):raise ValueError('SP2 reconstruction mismatch')
        q,_=quantize(p['qfc'],6,'sp2')
        if not np.array_equal(q,p['qfc']):raise ValueError('invalid SP2 codes')
    for k in ('b1','b2','bfc'):i32(p[k])
    return name

def transformed_conv(x,q,method='mul'):
    bt=tiles(x);n,ic,h,w,_=bt.shape;oc=q.shape[0]
    out=np.zeros((n,oc,h,w,4),np.int64)
    for o in range(oc):
        for i in range(ic):
            if method=='mul':p=bt[:,i]*q[o,i]
            elif method=='shift':p=shift_products(bt[:,i],q[o,i])
            else:raise ValueError('mul or shift arithmetic required')
            out[:,o]+=inverse(p)
    return i32(out)

def pool_codes(raw,b,shift):
    raw=i32(raw+np.asarray(b)[None,:,None,None,None])
    return np.clip(rne(raw,shift),0,255).max(-1).astype(np.int64)

def infer(x,p,method='mul',check=True):
    name=validate(p) if check else mode(p)
    x=np.asarray(x)
    single=x.ndim==2
    if single:x=x[None]
    if x.ndim!=3 or x.shape[1:]!=(28,28) or not np.issubdtype(x.dtype,np.integer) or x.min()<0 or x.max()>255:
        raise ValueError('N,28,28 unsigned-byte input required')
    if method=='shift' and name!='v25h':raise ValueError('int8 coefficients need multiplier backend')
    p1=pool_codes(transformed_conv(x[:,None],p['q1_td'],method),p['b1'],p['s1'])
    p2=pool_codes(transformed_conv(p1,p['q2_td'],method),p['b2'],p['s2'])
    flat=p2.reshape(len(x),48)
    if method=='mul':scores=flat@p['qfc'].T
    else:
        scores=np.zeros((len(x),4),np.int64)
        for cls in range(4):
            for term in range(2):scores[:,cls]+=shift_products(flat,p['fc_terms'][cls,:,term]).sum(-1)
    scores=i32(scores+p['bfc']);decisions=scores.argmax(1)
    result=dict(pool1=p1,pool2=p2,scores=scores,decision=decisions)
    return {k:v[0] for k,v in result.items()} if single else result

def infer_spatial(x,p):
    if validate(p)!='int8':raise ValueError('spatial equivalence only applies before transformed coding')
    x=np.asarray(x,np.int64);single=x.ndim==2
    if single:x=x[None]
    def pool(y,b,s):
        y=np.clip(rne(i32(y+b[None,:,None,None]),s),0,255)
        n,c,h,w=y.shape
        return y.reshape(n,c,h//2,2,w//2,2).max((3,5))
    p1=pool(direct_conv(x[:,None],p['q1_sp']),p['b1'],p['s1'])
    p2=pool(direct_conv(p1,p['q2_sp']),p['b2'],p['s2'])
    scores=i32(p2.reshape(len(x),48)@p['qfc'].T+p['bfc'])
    result=dict(pool1=p1,pool2=p2,scores=scores,decision=scores.argmax(1))
    return {k:v[0] for k,v in result.items()} if single else result

def bits_for(lo,hi):
    for b in range(1,64):
        if lo>=-(1<<(b-1)) and hi<(1<<(b-1)):return b
    raise OverflowError('range beyond int64')

def interval_scale(lo,hi,c):
    return min(lo*c,hi*c),max(lo*c,hi*c)

def range_report(p):
    """Conservative full-U8 proofs, not bounds observed on the training samples."""
    name=validate(p)
    bmin=(np.minimum(BM,0)*255).sum(1);bmax=(np.maximum(BM,0)*255).sum(1)
    conv=np.concatenate((p['q1_td'].reshape(2,49),p['q2_td'].reshape(6,49)))
    bounds=[]; layer_bounds=[]
    for co in conv:
        products=np.array([interval_scale(int(lo),int(hi),int(c)) for lo,hi,c in zip(bmin,bmax,co)])
        bounds.append(products)
        ylo=np.zeros(4,np.int64);yhi=np.zeros(4,np.int64)
        for mat,div in zip(INVERSE,DIVISIONS):
            lo=np.minimum(mat,0)@products[:,1]+np.maximum(mat,0)@products[:,0]
            hi=np.minimum(mat,0)@products[:,0]+np.maximum(mat,0)@products[:,1]
            ylo+=lo//div;yhi+=hi//div
        layer_bounds.append((ylo,yhi))
    for o in range(2):
        lo,hi=layer_bounds[o];i32(lo+p['b1'][o]);i32(hi+p['b1'][o])
    for o in range(3):
        lo=sum(layer_bounds[2+2*o+i][0] for i in range(2))
        hi=sum(layer_bounds[2+2*o+i][1] for i in range(2))
        i32(lo+p['b2'][o]);i32(hi+p['b2'][o])
    flo=(np.minimum(p['qfc'],0)*255).sum(1)+p['bfc']
    fhi=(np.maximum(p['qfc'],0)*255).sum(1)+p['bfc'];i32(flo);i32(fhi)
    for t in range(p['fc_terms'].shape[-1]):
        i32((np.minimum(p['fc_terms'][...,t],0)*255).sum(1))
        i32((np.maximum(p['fc_terms'][...,t],0)*255).sum(1))
    return dict(status='PASS_FULL_U8_INTERVAL_BOUNDS',activation_code_range=[0,255],
                conv_coefficients=conv.tolist(),conv_product_bounds=np.asarray(bounds).tolist(),
                B_bounds=np.stack((bmin,bmax),-1).tolist(),
                fc_score_bounds=np.stack((flo,fhi),-1).tolist(),
                note='Recomputed for these DASH coefficients; legacy V25-H lane widths are not reused.')

def load(path):
    with np.load(path,allow_pickle=False) as f:return {k:f[k] for k in f.files}

def export(p,directory,provenance=None):
    d=Path(directory);d.mkdir(parents=True,exist_ok=True);name=validate(p);proof=range_report(p)
    np.savez_compressed(d/'weights_int.npz',**p)
    for key in ('q1_td','q2_td','qfc','b1','b2','bfc'):
        np.savetxt(d/(key+'.csv'),p[key].reshape(-1,p[key].shape[-1]) if p[key].ndim>1 else p[key][None],fmt='%d',delimiter=',')
    manifest=dict(mode=name,channels=[1,2,3],fc=[48,4],classes=4,
                  class_names=['excellent','great','good','poor'],weight_bits=list(MODES[name]['weight_bits']),
                  activation_bits=[8,8],coding=dict(conv=MODES[name]['conv_coding'],fc=MODES[name]['fc_coding']),
                  s1=int(p['s1']),s2=int(p['s2']),rounding='nearest_even',activation='ReLU then saturate U8',
                  inverse='floor per 3x3/3x2/2x3/2x2 block, then sum input channels',
                  flatten='CHW',source_commit=SOURCE_COMMIT,
                  adaptation='DASH train-only scales, 32-bit bias/score; not legacy MNIST wrap/slice arithmetic',
                  provenance=provenance or {})
    (d/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (d/'range_proof.json').write_text(json.dumps(proof,indent=2)+'\n')
