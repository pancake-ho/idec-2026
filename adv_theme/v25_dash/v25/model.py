"""V25-H 1->2->3 / FC48->4, with genuine transformed-domain PoT QAT."""
import math
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from .spec import MODES,LANE_BW8
from .transforms import BM,GM,INVERSE,DIVISIONS
from .coding import table,quantize

def ste(x,value):return x+(value-x).detach()
def round_ste(x):return ste(x,torch.round(x))
def floor_ste(x):return ste(x,torch.floor(x))

def power_fake(x,bits,scheme):
    vs,_=table(int(bits),scheme)
    v=torch.tensor(vs,device=x.device,dtype=x.dtype)
    chosen=v[(x.detach()[...,None]-v).abs().argmin(-1)]
    return ste(x,chosen)

class V25DASH(nn.Module):
    def __init__(self,mode='fp32'):
        super().__init__()
        if mode not in ('fp32','int8','v25h'):raise ValueError('unknown mode')
        self.mode=mode;self.quant=None
        self.w1=nn.Parameter(torch.empty(2,1,5,5));self.b1=nn.Parameter(torch.zeros(2))
        self.w2=nn.Parameter(torch.empty(3,2,5,5));self.b2=nn.Parameter(torch.zeros(3))
        self.wfc=nn.Parameter(torch.empty(4,48));self.bfc=nn.Parameter(torch.zeros(4))
        for w in (self.w1,self.w2,self.wfc):nn.init.kaiming_uniform_(w,a=math.sqrt(5))
        self.register_buffer('bm',torch.tensor(BM,dtype=torch.float64))
        self.register_buffer('gm',torch.tensor(GM,dtype=torch.float64))
        for i,a in enumerate(INVERSE):self.register_buffer('im'+str(i),torch.tensor(a,dtype=torch.float64))

    def weight_codes(self):
        if self.quant is None or self.mode=='fp32':raise ValueError('calibrate an integer mode first')
        q=self.quant;cfg=MODES[self.mode];sp=[];td=[]
        for i,w in enumerate((self.w1,self.w2)):
            q8=round_ste(torch.clamp(w.double()/2.**q['ew8'][i],-128,127))
            if cfg['prune'][i]:
                q8=ste(q8,torch.where(q8.abs()<cfg['prune'][i],torch.zeros_like(q8),q8))
            k=floor_ste(q8/2.**(8-cfg['weight_bits'][i]));sp.append(k)
            transformed=k.flatten(2)@self.gm.T
            if self.mode=='v25h':
                bw=np.array(LANE_BW8)-(8-cfg['weight_bits'][i])
                # Group equal-width lanes; avoid a large codebook per tile.
                coded=torch.zeros_like(transformed)
                for b in sorted(set(bw.tolist())):
                    ids=np.flatnonzero(bw==b).tolist()
                    coded[...,ids]=power_fake(transformed[...,ids],b,'pot1')
                transformed=coded
            td.append(transformed)
        f8=round_ste(torch.clamp(self.wfc.double()/2.**q['ew8'][2],-128,127))
        if cfg['prune'][2]:f8=ste(f8,torch.where(f8.abs()<cfg['prune'][2],torch.zeros_like(f8),f8))
        fc=floor_ste(f8/2.**(8-cfg['weight_bits'][2]))
        if self.mode=='v25h':fc=power_fake(fc,6,'sp2')
        return sp,td,fc

    def _raw(self,x,sp,td):
        # Integer values are carried in float64 so every signed32 sum is exact.
        if self.mode=='int8':
            y=F.conv2d(x,sp)
            n,c,h,w=y.shape
            return y.reshape(n,c,h//2,2,w//2,2).permute(0,1,2,4,3,5).reshape(n,c,h//2,w//2,4)
        t=x.unfold(2,6,2).unfold(3,6,2).flatten(-2)
        bt=t@self.bm.T
        products=bt[:,None]*td[None,:,:,None,None,:]
        out=sum(floor_ste((products@getattr(self,'im'+str(i)).T)/div)
                for i,div in enumerate(DIVISIONS))
        return out.sum(2)

    @staticmethod
    def _bias(b,exp):
        return round_ste(torch.clamp(b.double()/2.**exp,-(1<<31),(1<<31)-1))

    def _pool(self,raw,b,raw_exp,activation_exp):
        unit=2.**(activation_exp-raw_exp)
        z=raw+self._bias(b,raw_exp)[None,:,None,None,None]
        return torch.clamp(round_ste(z/unit),0,255).max(-1).values

    def forward(self,x,maps=False):
        if x.ndim!=4 or tuple(x.shape[1:])!=(1,28,28):raise ValueError('N,1,28,28 required')
        if self.mode=='fp32':
            p1=F.max_pool2d(F.relu(F.conv2d(x,self.w1,self.b1)),2)
            p2=F.max_pool2d(F.relu(F.conv2d(p1,self.w2,self.b2)),2)
            scores=F.linear(p2.flatten(1),self.wfc,self.bfc)
        else:
            if self.quant is None:raise ValueError('integer-mode calibration missing')
            q=self.quant;sp,td,fc=self.weight_codes()
            codes=round_ste(x.double()*256)
            p1c=self._pool(self._raw(codes,sp[0],td[0]),self.b1,-8+q['ew1'],q['ea1'])
            p2c=self._pool(self._raw(p1c,sp[1],td[1]),self.b2,q['ea1']+q['ew2'],q['ea2'])
            score_exp=q['ea2']+q['ewfc']
            scores=(p2c.flatten(1)@fc.T+self._bias(self.bfc,score_exp))*2.**score_exp
            p1=p1c*2.**q['ea1'];p2=p2c*2.**q['ea2']
        return (scores,p1,p2) if maps else scores

    @torch.no_grad()
    def calibrate(self,x):
        if self.mode=='fp32':raise ValueError('select int8/v25h before calibration')
        def exponent(value):return math.ceil(math.log2(max(float(value),1e-12)))
        ew8=[exponent(w.abs().max()/127) for w in (self.w1,self.w2,self.wfc)]
        bits=MODES[self.mode]['weight_bits']
        self.quant=dict(ew8=ew8,ew1=ew8[0]+8-bits[0],ew2=ew8[1]+8-bits[1],ewfc=ew8[2]+8-bits[2])
        q=self.quant;sp,td,_=self.weight_codes();codes=x.double()*256
        raw_exp=-8+q['ew1']
        raw=self._raw(codes,sp[0],td[0])+self._bias(self.b1,raw_exp)[None,:,None,None,None]
        q['ea1']=max(exponent(raw.clamp(min=0).max()*2.**raw_exp/255),raw_exp)
        p1=self._pool(self._raw(codes,sp[0],td[0]),self.b1,raw_exp,q['ea1'])
        raw_exp=q['ea1']+q['ew2']
        raw=self._raw(p1,sp[1],td[1])+self._bias(self.b2,raw_exp)[None,:,None,None,None]
        q['ea2']=max(exponent(raw.clamp(min=0).max()*2.**raw_exp/255),raw_exp)
        for s in (q['ea1']+8-q['ew1'],q['ea2']-q['ea1']-q['ew2']):
            if not 0<=s<=31:raise ValueError('calibration requires unsupported shift')
        return q

    @torch.no_grad()
    def export_integer(self):
        from .integer import validate,range_report
        q=self.quant;sp,td,fc=self.weight_codes()
        def arr(x):return torch.round(x).detach().cpu().numpy().astype(np.int64)
        p=dict(mode=np.array(self.mode),q1_sp=arr(sp[0]),q2_sp=arr(sp[1]),
               q1_td=arr(td[0]),q2_td=arr(td[1]),qfc=arr(fc),
               b1=arr(self._bias(self.b1,-8+q['ew1'])),b2=arr(self._bias(self.b2,q['ea1']+q['ew2'])),
               bfc=arr(self._bias(self.bfc,q['ea2']+q['ewfc'])),
               s1=np.array(q['ea1']+8-q['ew1'],np.int64),s2=np.array(q['ea2']-q['ea1']-q['ew2'],np.int64))
        p['fc_terms']=p['qfc'][...,None] if self.mode=='int8' else quantize(p['qfc'],6,'sp2')[1]
        validate(p);range_report(p);return p
