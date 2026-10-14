"""Emit auditable, statically unrolled RTL for one fixed model architecture.

Both engines have the same ports and 7 registered stages (edge offset 6),
II=1, signed exact arithmetic. The direct reference shares its first 40
multipliers with FC; the optimized version has 40 physical multipliers.
"""
from pathlib import Path
import json,math
from ..integer.arithmetic import A,B,G
from ..spec import COORDS

ROOT=Path(__file__).resolve().parents[3]
def add(terms):
    terms=list(terms)
    if not terms:return "32'sd0"
    if len(terms)==1:return terms[0]
    n=len(terms)//2;return '('+add(terms[:n])+' + '+add(terms[n:])+')'
def lin(terms):
    result=[]
    for coeff,term in terms:
        if not coeff:continue
        z=term if abs(coeff)==1 else f'({term} <<< {int(math.log2(abs(coeff)))})'
        result.append(z if coeff>0 else f'(-{z})')
    return add(result)
def ext(name,bits):return f'$signed({{{{{32-bits}{{{name}[{bits-1}]}}}}, {name}}})' if bits<32 else name
def sw(lo,hi):
    for b in range(2,32):
        if -(1<<(b-1))<=lo and hi<1<<(b-1):return b

PORTS='''(
 input wire clk, input wire rst_n, input wire req_valid, input wire req_fc,
 input wire [15:0] req_tag,
 input wire [287:0] req_tile, input wire [199:0] req_kernel,
 input wire [439:0] req_fca, input wire [319:0] req_fcw,
 output wire rsp_valid, output wire rsp_fc, output wire [15:0] rsp_tag,
 output wire [127:0] rsp_tile, output wire signed [31:0] rsp_sum
);
 reg [6:0] v, mode;
 reg [15:0] tag [0:6];
 reg signed [11:0] ra[0:39]; reg signed [7:0] rb[0:39];
 reg signed [31:0] cv6[0:3]; reg signed [31:0] fc6;
 integer i;
 assign rsp_valid=v[6]; assign rsp_fc=mode[6]; assign rsp_tag=tag[6];
 assign rsp_sum=fc6;
 genvar o; generate for(o=0;o<4;o=o+1) begin assign rsp_tile[32*o+:32]=cv6[o]; end endgenerate
'''
P0='''
 always @(posedge clk) begin
  if(!rst_n) begin v<=0;mode<=0;fc6<=0;for(i=0;i<4;i=i+1)cv6[i]<=0; end
  else begin
   v<={v[5:0],req_valid};mode<={mode[5:0],req_fc};tag[0]<=req_tag;
   for(i=1;i<7;i=i+1)tag[i]<=tag[i-1];
   if(req_valid) begin
    if(req_fc) begin
     for(i=0;i<40;i=i+1)begin ra[i]<=$signed({1'b0,req_fca[11*i+:11]});rb[i]<=$signed(req_fcw[8*i+:8]);end
    end else begin
     for(i=0;i<36;i=i+1)ra[i]<=$signed({4'b0,req_tile[8*i+:8]});
     for(i=36;i<40;i=i+1)ra[i]<=0;
     for(i=0;i<25;i=i+1)rb[i]<=$signed(req_kernel[8*i+:8]);
     for(i=25;i<40;i=i+1)rb[i]<=0;
    end
   end
'''
def engine(kind):
    opt=kind=='pfdw';decl=[];st={i:[] for i in range(1,7)};bounds=[]
    if opt:
        decl+=['reg signed [11:0] xa1[0:39];reg signed [9:0] wb1[0:39];']
        st[1]+=['if(mode[0]) begin for(i=0;i<40;i=i+1)begin xa1[i]<=ra[i];wb1[i]<=rb[i];end end else begin']
        st[2]+=['if(mode[1]) begin']
        off=0;uoff=0;hoff=0;blocks=[]
        for r,c,kr,kc,bits in [(0,0,3,3,8),(0,3,3,2,6),(3,0,2,3,6)]:
            ar,ac=kr+1,kc+1;blocks.append((off,uoff,hoff,kr,kc));
            for x in range(ar):
                for y in range(ac):
                    terms=[(int(B[kc][y,j]),ext(f'ra[{(r+x)*6+c+j}]',12)) for j in range(ac)]
                    st[1].append(f'xa1[{off+x*ac+y}] <= {lin(terms)};')
            for x in range(kr):
                for y in range(ac):
                    terms=[(int(G[kc][y,j]),ext(f'rb[{(r+x)*5+c+j}]',8)) for j in range(kc)]
                    st[1].append(f'wb1[{uoff+x*ac+y}] <= {lin(terms)};')
            for x in range(ar):
                for y in range(ac):
                    lane=off+x*ac+y;coef=G[kr][x,:,None]*G[kc][y,None,:]
                    lo=int((coef.clip(0)*-(1<<(bits-1))+coef.clip(max=0)*((1<<(bits-1))-1)).sum())
                    hi=int((coef.clip(0)*((1<<(bits-1))-1)+coef.clip(max=0)*-(1<<(bits-1))).sum())
                    bw=max(6,sw(lo,hi));bounds.append(dict(lane=lane,aw=12,bw=bw,pw=12+bw,weight_min=lo,weight_max=hi))
                    st[2].append(f'a2_{lane}<=xa1[{lane}];b2_{lane}<=wb1[{lane}];')
            off+=ar*ac;uoff+=kr*ac;hoff+=ar*2
        st[1]+=[f'wb1[{j}]<=0;' for j in range(uoff,40)];st[1].append('end')
        st[2].append('end else begin')
        for off,uo,ho,kr,kc in blocks:
            ar,ac=kr+1,kc+1
            for x in range(ar):
                for y in range(ac):
                    lane=off+x*ac+y
                    st[2].append(f'a2_{lane}<={lin((int(B[kr][x,j]),ext(f"xa1[{off+j*ac+y}]",12)) for j in range(ar))};')
                    st[2].append(f'b2_{lane}<={lin((int(G[kr][x,j]),ext(f"wb1[{uo+j*ac+y}]",10)) for j in range(kr))};')
        st[2].append('end')
        decl+=['reg signed [31:0] h4[0:21];reg signed [31:0] b5[0:11];']
        st[4].append('if(!mode[3]) begin')
        st[5].append('if(!mode[4]) begin')
        for block,(off,uo,ho,kr,kc) in enumerate(blocks):
            ar,ac=kr+1,kc+1
            for x in range(ar):
                for y in range(2):
                    terms=[]
                    for j in range(ac):
                        k=off+x*ac+j;terms.append((int(A[kc][y,j]),ext(f'p3_{k}',bounds[k]['pw'])))
                    st[4].append(f'h4[{ho+x*2+y}]<={lin(terms)};')
            for x in range(2):
                for y in range(2):st[5].append(f'b5[{block*4+x*2+y}]<={lin((int(A[kr][x,j]),f"h4[{ho+j*2+y}]") for j in range(ar))};')
        st[4].append('end');st[5].append('end')
        st[6]+=['if(!mode[5]) begin']+[f'cv6[{k}]<=(b5[{k}] >>> 2)+(b5[{4+k}] <<< 1)+(b5[{8+k}] <<< 1);' for k in range(4)]+['end']
    else:
        decl+=['reg signed [11:0] xa1[0:83];reg signed [7:0] wb1[0:83];',
               'reg signed [31:0] c4[0:3];reg signed [31:0] c5[0:3];']
        st[1].append('if(mode[0]) begin')
        for k in range(84):st[1].append(f'xa1[{k}]<='+ (f'ra[{k}];wb1[{k}]<=rb[{k}];' if k<40 else f"0;wb1[{k}]<=0;"))
        st[1].append('end else begin')
        for out in range(4):
            rr,cc=out//2,out%2
            for j,(r,c) in enumerate(COORDS):
                k=out*21+j;delta=2 if r>=3 or c>=3 else 0
                st[1].append(f'xa1[{k}]<=ra[{(rr+r)*6+cc+c}];wb1[{k}]<=({ext(f"rb[{r*5+c}]",8)} <<< {delta});')
        st[1].append('end')
        for k in range(84):
            aw=12 if k<40 else 9;bounds.append(dict(lane=k,aw=aw,bw=8,pw=aw+8))
            st[2].append(f'a2_{k}<=xa1[{k}];b2_{k}<=wb1[{k}];')
        st[4].append('if(!mode[3]) begin')
        for out in range(4):st[4].append(f'c4[{out}]<={add(ext(f"p3_{k}",bounds[k]["pw"]) for k in range(out*21,(out+1)*21))};')
        st[4].append('end');st[5].append('if(!mode[4])for(i=0;i<4;i=i+1)c5[i]<=c4[i];')
        st[6].append('if(!mode[5])for(i=0;i<4;i=i+1)cv6[i]<=c5[i];')
    for item in bounds:
        k,aw,bw,pw=[item[x] for x in ['lane','aw','bw','pw']]
        decl.append(f'reg signed [{aw-1}:0] a2_{k};reg signed [{bw-1}:0] b2_{k};reg signed [{pw-1}:0] p3_{k};wire signed [{pw-1}:0] prod_{k};')
        decl.append(f'dash_booth #(.AW({aw}),.BW({bw})) m{k}(a2_{k},b2_{k},prod_{k});')
        st[3].append(f'p3_{k}<=prod_{k};')
    decl+=['reg signed [31:0] f4[0:9];reg signed [31:0] f5[0:1];']
    st[4].append('if(mode[3]) begin')
    for j in range(10):st[4].append(f'f4[{j}]<={add(ext(f"p3_{k}",bounds[k]["pw"]) for k in range(j*4,j*4+4))};')
    st[4].append('end');st[5].append('if(mode[4])begin')
    for j in range(2):st[5].append(f'f5[{j}]<={add(f"f4[{k}]" for k in range(j*5,j*5+5))};')
    st[5].append('end');st[6].append('if(mode[5])fc6<=f5[0]+f5[1];')
    body='\n'.join(f'if(v[{i-1}])begin\n'+ '\n'.join(st[i])+'\nend' for i in range(1,7))
    text='`timescale 1ns/1ps\n// GENERATED by src/dash_cnn/hardware/generate.py; do not hand-edit.\nmodule dash_engine_'+kind+PORTS+'\n'.join(decl)+P0+body+'\nend\nend\nendmodule\n'
    return text,bounds

def main():
    report={}
    for kind in ['direct','pfdw']:
        source,bounds=engine(kind);(ROOT/'rtl'/('dash_engine_'+kind+'.sv')).write_text(source);report[kind]=bounds
    (ROOT/'docs'/'guaranteed_lane_ranges.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
