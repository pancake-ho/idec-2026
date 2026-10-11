import sys,json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'src'))
from arithmetic import conv_direct
from integer import rne_shift,dwm_tile,effective,infer,validate,export,load
from data import ssim_local,grade,validate_splits
from spec import counts

def fixture(seed=2026):
    rng=np.random.default_rng(seed)
    def w(shape):
        z=rng.integers(-32,32,shape,dtype=np.int64);z[...,:3,:3]=rng.integers(-128,128,z[...,:3,:3].shape);z[...,3:,3:]=0;return z
    return dict(q1=w((6,1,5,5)),q2=w((3,12,6,5,5)),qfc=rng.integers(-32,32,(3,192),dtype=np.int64),
        b1=rng.integers(-100,100,6,dtype=np.int64),b2=rng.integers(-100,100,(3,12),dtype=np.int64),
        bfc=rng.integers(-100,100,3,dtype=np.int64),s1=np.array(8),s2=np.array(9))
def main():
    rng=np.random.default_rng(2026);p=fixture();validate(p)
    rounds=0
    for s in range(0,12):
        x=np.arange(-4096,4097,dtype=np.int64)
        assert np.array_equal(rne_shift(x,s),np.rint(x/2.**s).astype(np.int64));rounds+=len(x)
    tilecases=0
    for j in range(1000):
        x=rng.integers(0,256,(6,6),dtype=np.int64);q=p['q2'][j%3,j%12,j%6]
        if j<4:x.fill(255 if j%2 else 0)
        assert np.array_equal(dwm_tile(x,q),conv_direct(x[None],effective(q)[None,None])[0]);tilecases+=1
    images=[np.zeros((28,28),np.uint8),np.full((28,28),255,np.uint8),rng.integers(0,256,(28,28),dtype=np.uint8),((np.indices((28,28)).sum(0)%2)*255).astype(np.uint8)]
    networks=0
    for x in images:
        for d in range(3):
            a=infer(x,p,d,'direct');b=infer(x,p,d,'dwm')
            for k in a:assert np.array_equal(a[k],b[k]);
            networks+=1
    x=images[2];assert abs(ssim_local(x,x)-1)<1e-12
    assert grade(.97)==0 and grade(.90)==1 and grade(.899)==2
    assert ssim_local(np.zeros((28,28)),np.full((28,28),255))<.01
    dst=ROOT/'tests'/'fixtures';export(p,dst)
    for k in p:assert np.array_equal(p[k],load(dst/'weights_int.npz')[k])
    (dst/'NOTICE.txt').write_text('SYNTHETIC RANDOM WEIGHTS FOR ARITHMETIC/RTL TESTS ONLY. NOT A TRAINED QUALITY MODEL.\n')
    for i,x in enumerate(images):
        (dst/f'input_{i}.mem').write_text(''.join(f'{v:02x}\n' for v in x.ravel()))
    # RTL test profile 3 must fall back to shared profile 0.
    for i,d in enumerate([0,1,2,3]):
        z=infer(images[i],p,d if d<3 else 0)
        (dst/f'expected_{i}.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in z['scores']))
    report=dict(status='PASS',random_tile_cases=tilecases,network_cases=networks,rounding_cases=rounds,
        label_identity_and_boundaries=True,export_roundtrip=True,counts=counts(),real_video_accuracy='NOT_MEASURED',ppa='NOT_MEASURED')
    (ROOT/'results'/'python_validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
