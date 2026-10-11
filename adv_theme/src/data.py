"""Aligned local labels and source-disjoint prepared data. No reference at inference."""
import hashlib,json
from pathlib import Path
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from spec import SSIM_THRESHOLDS

def ssim_local(reference,distorted):
    a=np.asarray(reference,np.float64);b=np.asarray(distorted,np.float64)
    if a.shape!=(28,28) or b.shape!=a.shape:raise ValueError('SSIM requires aligned 28x28 patches')
    if not np.isfinite(a).all() or not np.isfinite(b).all() or min(a.min(),b.min())<0 or max(a.max(),b.max())>255:raise ValueError('Y range')
    g=np.exp(-np.arange(-5,6,dtype=float)**2/(2*1.5**2));g/=g.sum();win=g[:,None]*g[None,:]
    blur=lambda x:np.einsum('ijab,ab->ij',sliding_window_view(x,(11,11)),win)
    ma=blur(a);mb=blur(b);va=np.maximum(0,blur(a*a)-ma*ma);vb=np.maximum(0,blur(b*b)-mb*mb);cov=blur(a*b)-ma*mb
    c1=(.01*255)**2;c2=(.03*255)**2
    score=((2*ma*mb+c1)*(2*cov+c2))/((ma*ma+mb*mb+c1)*(va+vb+c2))
    return float(np.clip(score.mean(),-1,1))

def grade(ssim):
    a,b=SSIM_THRESHOLDS
    return 0 if ssim>=b else (1 if ssim>=a else 2)

def features(x,bitrate_bps,width,height,fps,profile):
    """Metadata controls and inexpensive spatial-feature controls, all observable."""
    x=x.astype(np.float64)/255;dx=np.diff(x,axis=1);dy=np.diff(x,axis=0)
    meta=np.array([np.log2(max(bitrate_bps/(width*height*fps),1e-9)),np.log2(width),np.log2(height),float(profile==1),float(profile==2)])
    spatial=np.array([x.mean(),x.std(),np.abs(dx).mean(),np.abs(dy).mean(),
        np.mean(np.diff(x,2,axis=1)**2),np.mean(np.diff(x,2,axis=0)**2)])
    return meta,np.r_[meta,spatial]

def validate_splits(train,val,test=None):
    seq=[train,val]+([] if test is None else [test]);sets=[];hashes=[]
    for d in seq:
        n=len(d['x'])
        if d['x'].dtype!=np.uint8 or d['x'].shape!=(n,28,28) or not n:raise ValueError('empty or invalid patches')
        for k in ['y','profile','source_id','source_sha256','sample_id','ssim','bitrate_bps']:
            if len(d[k])!=n:raise ValueError(k+' length')
        for k,lo,hi in [('y',0,2),('profile',1,2)]:
            if not np.issubdtype(d[k].dtype,np.integer) or d[k].min()<lo or d[k].max()>hi:raise ValueError(k+' range')
        if not np.isfinite(d['ssim']).all() or np.any(d['y']!=np.array([grade(v) for v in d['ssim']])):raise ValueError('label/SSIM contract')
        if len(set(d['sample_id'].astype(str)))!=n:raise ValueError('duplicate sample_id')
        if '' in set(d['source_id'].astype(str)) or '' in set(d['source_sha256'].astype(str)):raise ValueError('empty source identity')
        sets.append(set(d['source_id'].astype(str)));hashes.append(set(d['source_sha256'].astype(str)))
    for i in range(len(seq)):
        for j in range(i):
            if sets[i]&sets[j] or hashes[i]&hashes[j]:raise ValueError('source leakage between splits')
    return {'source_counts':[len(s) for s in sets],'source_id_and_hash_disjoint':True}

def load(path):
    with np.load(path,allow_pickle=False) as f:return {k:f[k] for k in f.files}

def metrics(y,pred,profile):
    def calc(a,b):
        cm=np.zeros((3,3),np.int64);np.add.at(cm,(a,b),1)
        den=cm.sum(0)+cm.sum(1);f1=np.divide(2*np.diag(cm),den,out=np.zeros(3),where=den>0)
        return dict(n=int(cm.sum()),accuracy=float(np.trace(cm)/max(cm.sum(),1)),macro_f1=float(f1.mean()),
                    severe_missed_as_low=float(cm[2,0]/max(cm[2].sum(),1)),confusion=cm.tolist())
    return dict(overall=calc(y,pred),profiles={str(d):calc(y[profile==d],pred[profile==d]) for d in (1,2)})

def sha256(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
