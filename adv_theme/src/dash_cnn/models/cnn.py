"""Four-class AVC CNN. Shared weights; no codec adapter in the first experiment."""
import math
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from ..spec import VARIANTS,code_layout,NUM_CLASSES

def fake(v,lo,hi):
    z=torch.clamp(v,min=lo,max=hi)
    return z+(torch.round(z)-z).detach()

class DASHCNN(nn.Module):
    def __init__(self,variant='final'):
        super().__init__();self.variant=variant;self.v=VARIANTS[variant]
        coords=[(r,c) for r in range(5) for c in range(5) if not self.v['mask'] or r<3 or c<3]
        self.n=len(coords);sc=torch.zeros(self.n,5,5)
        for i,(r,c) in enumerate(coords):sc[i,r,c]=1
        self.register_buffer('scatter',sc)
        lo,hi,delta=code_layout(self.v)
        for k,a in [('lo',lo),('hi',hi),('delta',delta)]:self.register_buffer(k,torch.tensor(a,dtype=torch.float32))
        self.w1=nn.Parameter(torch.empty(6,1,self.n));self.b1=nn.Parameter(torch.zeros(6))
        self.w2=nn.Parameter(torch.empty(12,6,self.n));self.b2=nn.Parameter(torch.zeros(12))
        self.wfc=nn.Parameter(torch.empty(NUM_CLASSES,192));self.bfc=nn.Parameter(torch.zeros(NUM_CLASSES))
        for w in [self.w1,self.w2,self.wfc]:nn.init.kaiming_uniform_(w,a=math.sqrt(5))
        self.quant=None
    def kernels(self,profile):
        if profile not in (0,1):raise ValueError('AVC shared only')
        w=self.w2;b=self.b2
        return torch.einsum('oik,krc->oirc',self.w1,self.scatter),torch.einsum('oik,krc->oirc',w,self.scatter),b
    def qw(self,w,e):
        s=2.**e*2.**self.delta
        return fake(w/s,self.lo,self.hi)*s
    def qb(self,b,e):return fake(b/2.**e,-2**31,2**31-1)*2.**e
    def qa(self,x,e,bits):return fake(x/2.**e,0,2**bits-1)*2.**e
    def forward(self,x,profile=0,maps=False):
        if x.ndim!=4 or tuple(x.shape[1:])!=(1,28,28):raise ValueError('N,1,28,28 required')
        w1,w2,b2=self.kernels(profile);b1=self.b1;wf=self.wfc;bf=self.bfc
        if self.quant is not None:
            q=self.quant;w1=self.qw(w1,q['ew1']);w2=self.qw(w2,q['ew2'])
            lim=2**(self.v['fc_bits']-1);wf=fake(wf/2.**q['ewfc'],-lim,lim-1)*2.**q['ewfc']
            b1=self.qb(b1,-8+q['ew1']);b2=self.qb(b2,q['ea1']+q['ew2']);bf=self.qb(bf,q['ea2']+q['ewfc'])
        y=F.conv2d(x,w1,b1)
        y=F.relu(y) if self.quant is None else self.qa(y,q['ea1'],self.v['a1_bits'])
        p1=F.max_pool2d(y,2);y=F.conv2d(p1,w2,b2)
        y=F.relu(y) if self.quant is None else self.qa(y,q['ea2'],self.v['a2_bits'])
        p2=F.max_pool2d(y,2);scores=F.linear(p2.flatten(1),wf,bf)
        return (scores,p1,p2) if maps else scores
    def train_base(self):
        for p in self.parameters():p.requires_grad_(True)
    @torch.no_grad()
    def calibrate(self,x):
        exp=lambda x:math.ceil(math.log2(max(float(x),1e-12)))
        w1,w2,_=self.kernels(0);cap=self.hi.clamp(min=1)*2.**self.delta
        e1=exp((w1.abs()/cap).max());e2=exp((w2.abs()/cap).max())
        ef=exp(self.wfc.abs().max()/(2**(self.v['fc_bits']-1)-1))
        y=F.conv2d(x,self.qw(w1,e1),self.qb(self.b1,-8+e1))
        a1=max(exp(y.clamp(min=0).max()/(2**self.v['a1_bits']-1)),-8+e1)
        p1=F.max_pool2d(self.qa(y,a1,self.v['a1_bits']),2)
        y=F.conv2d(p1,self.qw(w2,e2),self.qb(self.b2,a1+e2))
        a2=max(exp(y.clamp(min=0).max()/(2**self.v['a2_bits']-1)),a1+e2)
        self.quant=dict(ew1=e1,ew2=e2,ewfc=ef,ea1=a1,ea2=a2)
        if not 0<=a1+8-e1<=31 or not 0<=a2-a1-e2<=31:raise ValueError('unsupported shift')
        return self.quant
    @torch.no_grad()
    def export_integer(self):
        if self.quant is None:raise ValueError('quantization not calibrated')
        q=self.quant
        arr=lambda a:a.detach().cpu().double().numpy()
        lo,hi,delta=code_layout(self.v)
        enc=lambda w,e:np.clip(np.rint(arr(w)/(2.**e*2.**delta)),lo,hi).astype(np.int64)
        def bias(b,e):
            z=np.rint(arr(b)/2.**e)
            if z.min()<-2**31 or z.max()>2**31-1:raise OverflowError('bias')
            return z.astype(np.int64)
        ks=[self.kernels(0)];lim=2**(self.v['fc_bits']-1)
        p=dict(q1=enc(ks[0][0],q['ew1']),q2=enc(ks[0][1],q['ew2']),
            qfc=np.clip(np.rint(arr(self.wfc)/2.**q['ewfc']),-lim,lim-1).astype(np.int64),
            b1=bias(self.b1,-8+q['ew1']),b2=bias(ks[0][2],q['ea1']+q['ew2']),
            bfc=bias(self.bfc,q['ea2']+q['ewfc']),s1=np.array(q['ea1']+8-q['ew1']),s2=np.array(q['ea2']-q['ea1']-q['ew2']))
        from ..integer.model import validate
        validate(p,self.variant);return p
