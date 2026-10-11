"""Exact integer inference. All arithmetic checks use int64 before narrowing."""
import json
from pathlib import Path
import numpy as np
from arithmetic import A,B,G,BLOCKS,conv_direct,assert_i32
from spec import VARIANTS,code_layout

def effective(q,variant='final'):
    return np.asarray(q,np.int64)*(2**code_layout(VARIANTS[variant])[2])

def rne_shift(x,shift):
    x=np.asarray(x,np.int64);s=int(shift)
    if not 0<=s<=31:raise ValueError('shift outside 0..31')
    if not s:return x.copy()
    base=x>>s;rem=x-(base<<s);half=1<<(s-1)
    return base+((rem>half)|((rem==half)&((base&1)!=0)))

def dwm_tile(x,q,variant='final'):
    y=np.zeros((2,2),np.int64);delta=code_layout(VARIANTS[variant])[2]
    for r,c,kr,kc in BLOCKS:
        if VARIANTS[variant]['mask'] and r==3 and c==3:continue
        d=B[kr]@x[r:r+kr+1,c:c+kc+1]@B[kc].T
        u=G[kr]@q[r:r+kr,c:c+kc]@G[kc].T
        z=A[kr]@(d*u)@A[kc].T
        div=(2 if kr==3 else 1)*(2 if kc==3 else 1)
        if np.any(z%div):raise AssertionError('non-exact inverse transform')
        y+=(z//div)*(1<<int(delta[r,c]))
    return y

def conv_dwm(x,q,variant='final'):
    oc,ic=q.shape[:2];h,w=x.shape[-2]-4,x.shape[-1]-4
    if h%2 or w%2:raise ValueError('2x2 tiles require even output dimensions')
    out=np.zeros((oc,h,w),np.int64)
    for o in range(oc):
        for r in range(0,h,2):
            for c in range(0,w,2):
                for i in range(ic):out[o,r:r+2,c:c+2]+=dwm_tile(x[i,r:r+6,c:c+6],q[o,i],variant)
    return out

def validate(p,variant='final'):
    shapes={'q1':(6,1,5,5),'q2':(3,12,6,5,5),'qfc':(3,192),
            'b1':(6,),'b2':(3,12),'bfc':(3,)}
    for k,sh in shapes.items():
        a=np.asarray(p[k])
        if a.shape!=sh or not np.issubdtype(a.dtype,np.integer):raise ValueError(k+' shape/type')
    v=VARIANTS[variant];lo,hi,_=code_layout(v)
    for k in ['q1','q2']:
        if np.any(p[k]<lo) or np.any(p[k]>hi):raise ValueError(k+' invalid mask/weight code')
    if p['qfc'].min()<-(1<<(v['fc_bits']-1)) or p['qfc'].max()>=(1<<(v['fc_bits']-1)):raise ValueError('FC code')
    for k in ['s1','s2']:
        a=np.asarray(p[k])
        if a.ndim or not np.issubdtype(a.dtype,np.integer) or not 0<=int(a)<=31:raise ValueError(k+' shift')
    layers=[(effective(p['q1'],variant),p['b1'],255)]
    layers += [(effective(p['q2'][i],variant),p['b2'][i],(1<<v['a1_bits'])-1) for i in range(3)]
    layers += [(p['qfc'],p['bfc'],(1<<v['a2_bits'])-1)]
    for w,b,mx in layers:
        w=w.reshape(len(b),-1);assert_i32(b)
        assert_i32(mx*np.minimum(w,0).sum(1)+b);assert_i32(mx*np.maximum(w,0).sum(1)+b)

def pool(raw,b,shift,bits):
    raw=raw+b[:,None,None];assert_i32(raw)
    q=np.clip(rne_shift(raw,shift),0,(1<<bits)-1)
    ch,h,w=q.shape
    return q.reshape(ch,h//2,2,w//2,2).max((2,4))

def infer(x,p,profile=0,method='direct',variant='final'):
    validate(p,variant);x=np.asarray(x)
    if x.shape!=(28,28) or not np.issubdtype(x.dtype,np.integer) or x.min()<0 or x.max()>255:raise ValueError('uint8-range 28x28 required')
    if profile not in (0,1,2):raise ValueError('profile must be 0,1,2')
    v=VARIANTS[variant]
    if method=='direct':fn=lambda x,q:conv_direct(x,effective(q,variant))
    elif method=='dwm':fn=lambda x,q:conv_dwm(x,q,variant)
    else:raise ValueError('method')
    p1=pool(fn(x[None],p['q1']),p['b1'],p['s1'],v['a1_bits'])
    p2=pool(fn(p1,p['q2'][profile]),p['b2'][profile],p['s2'],v['a2_bits'])
    flat=p2.ravel();scores=p['bfc'].copy()
    for i in range(0,192,40):scores+=p['qfc'][:,i:i+40]@flat[i:i+40]
    assert_i32(scores)
    return dict(pool1=p1,pool2=p2,scores=scores,decision=int(np.argmax(scores)))

def load(path):
    with np.load(path,allow_pickle=False) as f:return {k:f[k] for k in f.files}

def export(p,directory,variant='final'):
    validate(p,variant);d=Path(directory);d.mkdir(parents=True,exist_ok=True)
    np.savez_compressed(d/'weights_int.npz',**p)
    for k in ['q1','q2','qfc','b1','b2','bfc']:
        bits=32 if k.startswith('b') else 8
        (d/(k+'.mem')).write_text(''.join(f'{int(x)&((1<<bits)-1):0{bits//4}x}\n' for x in p[k].ravel()))
    (d/'params.svh').write_text(f'`define DASH_S1 {int(p["s1"])}\n`define DASH_S2 {int(p["s2"])}\n')
    (d/'manifest.json').write_text(json.dumps(dict(variant=variant,shape='HWC input; OIHW kernel; CHW flatten',
        s1=int(p['s1']),s2=int(p['s2']),rounding='nearest_even',weight_words='byte sign-extended; logical packing is separate',
        profiles=['shared','avc','hevc']),indent=2)+'\n')
