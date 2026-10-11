"""Integer DWM matrices inherited from the team Adapt40 functional reference."""
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

B = {
    3: np.array([[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]],dtype=np.int64),
    2: np.array([[1,-1,0],[0,1,0],[0,-1,1]],dtype=np.int64),
}

G = {
    3: np.array([[2,0,0],[1,1,1],[1,-1,1],[0,0,2]],dtype=np.int64),
    2: np.array([[1,0],[1,1],[0,1]],dtype=np.int64),
}

A = {
    3: np.array([[1,1,1,0],[0,1,-1,-1]],dtype=np.int64),
    2: np.array([[1,1,0],[0,1,1]],dtype=np.int64),
}

BLOCKS = ((0,0,3,3),(0,3,3,2),(3,0,2,3),(3,3,2,2))

def conv_direct(x,w):
    x=np.asarray(x,dtype=np.int64);w=np.asarray(w,dtype=np.int64)
    return np.einsum('ihwkl,oikl->ohw',sliding_window_view(x,(5,5),axis=(1,2)),w)

def assert_i32(x):
    if np.min(x)<-(1<<31) or np.max(x)>(1<<31)-1:
        raise OverflowError("int32 accumulator would overflow")

