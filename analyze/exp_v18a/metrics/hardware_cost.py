"""Guaranteed shared operand widths and structural cost proxies; no ASIC PPA claims."""
import numpy as np
from exp_v18a.io.common import required_signed_bits
from exp_v18a.models.engine import AW,BW,PW,B3,B2,G3,G2,BLOCKS

def affine_interval(matrix, low, high):
    matrix=np.asarray(matrix)
    return (np.maximum(matrix,0)*low+np.minimum(matrix,0)*high).sum(axis=-1), \
           (np.maximum(matrix,0)*high+np.minimum(matrix,0)*low).sum(axis=-1)

def operand_bounds(activation_bits=11,weight_bits=8):
    """Guaranteed ranges for all unsigned activation and signed q-weight codes.

    These describe a proposed q-domain datapath with layer shifts restored
    AFTER each dot product. They are not a claim that the existing RTL shrinks.
    """
    if not 1<=activation_bits<=11 or not 2<=weight_bits<=8:
        raise ValueError("cost bounds support A1..11 unsigned and W2..8 signed")
    alo,ahi=0,(1<<activation_bits)-1
    blo,bhi=-(1<<(weight_bits-1)),(1<<(weight_bits-1))-1
    rows=[]
    for offset,r,c,rr,cc,n in BLOCKS:
        br,bc=(B3 if r==3 else B2),(B3 if c==3 else B2)
        gr,gc=(G3 if r==3 else G2),(G3 if c==3 else G2)
        al,ah=affine_interval(np.kron(br,bc),alo,ahi)
        bl,bh=affine_interval(np.kron(gr,gc),blo,bhi)
        for j in range(n):
            products=[int(al[j])*int(bl[j]),int(al[j])*int(bh[j]),int(ah[j])*int(bl[j]),int(ah[j])*int(bh[j])]
            rows.append(dict(lane=offset+j,a_low=int(al[j]),a_high=int(ah[j]),
                             b_low=int(bl[j]),b_high=int(bh[j]),p_low=min(products),p_high=max(products)))
    return rows

def shared_cost(wbits=(8,8,8),abits=(11,11)):
    """Layer max, then mode union. No empirical min/max is used to prove widths."""
    modes=[operand_bounds(8,int(wbits[0])),operand_bounds(int(abits[0]),int(wbits[1]))]
    rows=[]
    for j in range(49):
        abounds=[(m[j]["a_low"],m[j]["a_high"]) for m in modes]
        bbounds=[(m[j]["b_low"],m[j]["b_high"]) for m in modes]
        pbounds=[(m[j]["p_low"],m[j]["p_high"]) for m in modes]
        if j<48:
            ah=(1<<int(abits[1]))-1
            bl,bh=-(1<<(int(wbits[2])-1)),(1<<(int(wbits[2])-1))-1
            abounds.append((0,ah));bbounds.append((bl,bh));pbounds.append((ah*bl,ah*bh))
        wa=required_signed_bits(min(x[0] for x in abounds),max(x[1] for x in abounds))
        wb=required_signed_bits(min(x[0] for x in bbounds),max(x[1] for x in bbounds))
        wp=required_signed_bits(min(x[0] for x in pbounds),max(x[1] for x in pbounds))
        rows.append(dict(lane=j,baseline_aw=int(AW[j]),baseline_bw=int(BW[j]),baseline_pw=int(PW[j]),
                         proposed_aw=wa,proposed_bw=wb,proposed_pw=wp,
                         baseline_booth_rows=int((BW[j]+1)//2),proposed_booth_rows=(wb+1)//2,
                         needs_new_booth_reduction=int((wb+1)//2<4)))
    # Model is only a structural proxy for P2/P3, not total chip PPA.
    summary=dict(p2_register_bits=sum(r["proposed_aw"]+r["proposed_bw"] for r in rows),
                 p3_register_bits=sum(r["proposed_pw"] for r in rows),
                 multiplier_bitproduct=sum(r["proposed_aw"]*r["proposed_bw"] for r in rows),
                 booth_row_bitproxy=sum(r["proposed_booth_rows"]*(r["proposed_aw"]+r["proposed_bw"]+2) for r in rows),
                 lanes_requiring_booth_rewrite=sum(r["needs_new_booth_reduction"] for r in rows))
    return rows,summary
