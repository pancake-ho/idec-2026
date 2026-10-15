"""V25's 49-lane B/G/A order, with separate inverse floors for four blocks."""
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

B = {3: np.array([[1,0,-1,0],[0,1,1,0],[0,-1,1,0],[0,1,0,-1]], np.int64),
     2: np.array([[1,-1,0],[0,1,0],[0,-1,1]], np.int64)}
G = {3: np.array([[2,0,0],[1,1,1],[1,-1,1],[0,0,2]], np.int64),
     2: np.array([[1,0],[1,1],[0,1]], np.int64)}
A = {3: np.array([[1,1,1,0],[0,1,-1,-1]], np.int64),
     2: np.array([[1,1,0],[0,1,1]], np.int64)}
BLOCKS = ((0,0,3,3),(0,3,3,2),(3,0,2,3),(3,3,2,2))

def matrices():
    bm = np.zeros((49,36), np.int64); gm = np.zeros((49,25), np.int64)
    inverse = []; divisions = []; start = 0
    for r,c,kr,kc in BLOCKS:
        size = (kr+1)*(kc+1)
        ids_x = [(r+i)*6+c+j for i in range(kr+1) for j in range(kc+1)]
        ids_w = [(r+i)*5+c+j for i in range(kr) for j in range(kc)]
        bm[start:start+size, ids_x] = np.kron(B[kr], B[kc])
        gm[start:start+size, ids_w] = np.kron(G[kr], G[kc])
        im = np.zeros((4,49), np.int64)
        im[:, start:start+size] = np.kron(A[kr], A[kc])
        inverse.append(im); divisions.append((2 if kr==3 else 1)*(2 if kc==3 else 1))
        start += size
    return bm, gm, tuple(inverse), tuple(divisions)

BM, GM, INVERSE, DIVISIONS = matrices()

def tiles(x):
    """N,IC,H,W -> N,IC,pooled-H,pooled-W,49; tile stride is two."""
    x = np.asarray(x, np.int64)
    if x.ndim != 4 or min(x.shape[-2:]) < 6 or any((s-4)%2 for s in x.shape[-2:]):
        raise ValueError('even valid convolution dimensions required')
    t = sliding_window_view(x, (6,6), axis=(2,3))[:, :, ::2, ::2]
    return t.reshape(t.shape[:-2]+(36,)) @ BM.T

def inverse(products):
    p = np.asarray(products, np.int64)
    return sum((p @ mat.T)//div for mat,div in zip(INVERSE,DIVISIONS))

def direct_conv(x, w):
    sw = sliding_window_view(np.asarray(x,np.int64), (5,5), axis=(2,3))
    return np.einsum('nihwkl,oikl->nohw',sw,np.asarray(w,np.int64))
