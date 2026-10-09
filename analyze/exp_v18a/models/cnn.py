"""Full functional V18A CNN model. Reuses the unchanged Reference trace schema."""
from __future__ import annotations
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view
from exp_v18a.io.common import RTLReferenceCNN, RTLTrace, wrap_signed, part_select_signed
from exp_v18a.experiments.quantization import activation_quant
from exp_v18a.models import engine

def untile(raw):
    """[...,tile_row,tile_col,4] -> [...,output_row,output_col]."""
    prefix = raw.ndim - 3
    shape = raw.shape
    a = raw.reshape(shape[:-1]+(2,2))
    order = list(range(prefix)) + [prefix,prefix+2,prefix+1,prefix+3]
    return a.transpose(order).reshape(shape[:prefix]+(shape[-3]*2,shape[-2]*2))

class V18ACNN(RTLReferenceCNN):
    def __init__(self,params,abits=(11,11),rounding="floor"):
        super().__init__(params)
        self.abits = tuple(abits)
        self.rounding = rounding

    def _conv1(self,image):
        image = np.asarray(image,dtype=np.int64)
        if image.shape != (28,28):
            raise ValueError("image must have shape 28x28")
        engine.check_range(image,0,255,"image")
        tiles = sliding_window_view(image,(6,6))[::2,::2]
        raw = engine.conv(tiles[None,...],self.p.conv1_w[:,None,None,:,:])
        acc_math = untile(raw)
        acc20 = wrap_signed(acc_math,20)
        pre = part_select_signed(acc20,20,19,8)
        out = wrap_signed(pre+self.p.conv1_b[:,None,None],12)
        return out,acc_math,acc20

    def _conv2(self,x):
        x = np.asarray(x,dtype=np.int64)
        if x.shape != (3,12,12):
            raise ValueError("pool1 must have shape 3x12x12")
        tiles = sliding_window_view(x,(6,6),axis=(1,2))[:,::2,::2]
        raw = engine.conv(tiles[None,...],self.p.conv2_w[:,:,None,None,:,:])
        partial_math = untile(raw)
        partial20 = wrap_signed(partial_math,20)
        full_math = partial_math.sum(axis=1)
        acc20 = wrap_signed(partial20.sum(axis=1),20)
        internal14 = part_select_signed(acc20,20,19,6)
        pre = part_select_signed(internal14,14,13,1)
        out = wrap_signed(pre+self.p.conv2_b[:,None,None],12)
        return out,partial_math,partial20,full_math,acc20,internal14

    def _fully_connected(self,pool2):
        a = np.asarray(pool2,dtype=np.int64).reshape(48)
        acc_math = engine.fc(a[None,:],self.p.fc_w)+self.p.fc_b
        acc20 = wrap_signed(acc_math,20)
        logits = part_select_signed(acc20,20,18,7)
        return a,acc_math,acc20,logits

    def forward(self,image,return_trace=False):
        c1,c1math,c1acc = self._conv1(image)
        p1 = activation_quant(self._maxpool_relu(c1),self.abits[0],self.rounding)
        c2,c2partial,c2p20,c2full,c2acc,c2internal = self._conv2(p1)
        p2 = activation_quant(self._maxpool_relu(c2),self.abits[1],self.rounding)
        fi,fmath,facc,logits = self._fully_connected(p2)
        pred = int(np.argmax(logits))
        if not return_trace:
            return pred
        return pred,RTLTrace(input_image=np.asarray(image,dtype=np.int64),
            conv1_acc_math=c1math,conv1_acc20=c1acc,conv1_out=c1,pool1=p1,
            conv2_partial_math=c2partial,conv2_partial20=c2p20,conv2_full_math=c2full,
            conv2_acc20=c2acc,conv2_internal14=c2internal,conv2_out=c2,pool2=p2,
            fc_input=fi,fc_acc_math=fmath,fc_acc20=facc,logits=logits)

    def engine_requests(self,trace):
        """Logical operand order, NOT scheduler time order or a power trace."""
        tiles = sliding_window_view(trace.input_image,(6,6))[::2,::2]
        for oc in range(3):
            _,s = engine.conv(tiles,self.p.conv1_w[oc],True)
            yield "conv1",oc,-1,s
        tiles = sliding_window_view(trace.pool1,(6,6),axis=(1,2))[:,::2,::2]
        for oc in range(3):
            for ic in range(3):
                _,s = engine.conv(tiles[ic],self.p.conv2_w[oc,ic],True)
                yield "conv2",oc,ic,s
        _,s = engine.fc(trace.fc_input[None,:],self.p.fc_w,True)
        yield "fc",-1,-1,s
