"""Generate coefficient-specific 49-lane engines and adapt the frozen V25-H streaming controller."""
import json
from pathlib import Path
import re
import numpy as np
from .transforms import BM,A,BLOCKS
from .integer import validate,range_report,bits_for,interval_scale

ROOT=Path(__file__).resolve().parents[1]

def literal(x,bits):return ('-' if x<0 else '')+str(bits)+"'sd"+str(abs(int(x)))

def sx(name,source,target):
    if target==source:return '$signed('+name+')'
    if target<source:return '$signed('+name+'['+str(target-1)+':0])'
    return '$signed({{'+str(target-source)+'{'+name+'['+str(source-1)+']}},'+name+'})'

def total(terms):
    if not terms:return "32'sd0"
    if len(terms)==1:return terms[0]
    mid=len(terms)//2
    return '('+total(terms[:mid])+' + '+total(terms[mid:])+')'

def lookup(p,lane):
    """{fc,conv2,tag[4:0]} distinguishes all coefficient rows."""
    result={o*4:int(p['q1_td'][o,0,lane]) for o in range(2)}
    result.update({32+o*4+i:int(p['q2_td'][o,i,lane]) for o in range(3) for i in range(2)})
    for c in range(4):
        for term in range(p['fc_terms'].shape[-1]):
            result[64+16*term+c]=int(p['fc_terms'][c,lane,term]) if lane<48 else 0
    return result

def add_bounds(bounds):return sum(x[0] for x in bounds),sum(x[1] for x in bounds)

def generate_engine(p,backend='shift'):
    name=validate(p);proof=range_report(p)
    if backend not in ('mul','shift') or backend=='shift' and name!='v25h':raise ValueError('unsupported backend')
    bm=np.array(proof['B_bounds']);cp=np.array(proof['conv_product_bounds'])
    conv_bounds=np.stack((cp[:,:,0].min(0),cp[:,:,1].max(0)),1)
    aw=[];pw=[];bw=[];fc_bounds=[];maps=[]
    for i in range(49):
        m=lookup(p,i);maps.append(m)
        fc=[interval_scale(0,255,c) for k,c in m.items() if k>=64]
        fb=(min(v[0] for v in fc),max(v[1] for v in fc));fc_bounds.append(fb)
        aw.append(bits_for(min(int(bm[i,0]),0),max(int(bm[i,1]),255 if i<48 else 0)))
        bw.append(bits_for(min(m.values()),max(m.values())))
        pw.append(bits_for(min(int(conv_bounds[i,0]),fb[0]),max(int(conv_bounds[i,1]),fb[1])))
    h=[];v=[];offset=0
    for bi,(_,_,kr,kc) in enumerate(BLOCKS):
        for r in range(kr+1):
            for col in range(2):
                ids=[offset+r*(kc+1)+j for j,c in enumerate(A[kc][col]) if c]
                coeff=[int(c) for c in A[kc][col] if c]
                bounds=add_bounds([interval_scale(*map(int,conv_bounds[k]),c) for k,c in zip(ids,coeff)])
                h.append(dict(name=f'h_{bi}_{r}_{col}',ids=ids,coeff=coeff,bounds=bounds,width=bits_for(*bounds)))
        for row in range(2):
            for col in range(2):
                items=[z for z in h if z['name'].startswith(f'h_{bi}_') and int(z['name'].split('_')[-1])==col]
                selected=[(items[j],int(c)) for j,c in enumerate(A[kr][row]) if c]
                bounds=add_bounds([interval_scale(*z['bounds'],c) for z,c in selected])
                v.append(dict(name=f'z_{bi}_{row*2+col}',items=selected,bounds=bounds,width=bits_for(*bounds)))
        offset+=(kr+1)*(kc+1)
    f4=[add_bounds(fc_bounds[i:i+3]) for i in range(0,48,3)]
    f5=[add_bounds(f4[i:i+4]) for i in range(0,16,4)]
    f4w=[bits_for(*x) for x in f4];f5w=[bits_for(*x) for x in f5]
    s=['`timescale 1ps/1ps', '// V25-derived 49-lane coefficient-specific shared pipeline; generated for DASH.',
       f'// mode={name}, backend={backend}; P0 request -> P6 response, II=1.',
       'module v25_dash_engine(input logic clk,rst_n,req_valid,req_is_fc, input logic [15:0] req_tag,',
       'input wire signed [8:0] conv_tile[0:5][0:5], input wire signed [8:0] fc_a[0:47],',
       'output logic rsp_valid,rsp_is_fc, output logic [15:0] rsp_tag,',
       'output logic signed [31:0] conv_y00,conv_y01,conv_y10,conv_y11,fc_sum);',
       'logic [6:0] valid_pipe,mode_pipe; logic [15:0] tag_pipe[0:6]; integer k;',
       'always @(posedge clk) begin if(!rst_n)begin valid_pipe<=0;mode_pipe<=0;for(k=0;k<7;k=k+1)tag_pipe[k]<=0;end',
       'else begin valid_pipe<={valid_pipe[5:0],req_valid};mode_pipe<={mode_pipe[5:0],req_is_fc};',
       'tag_pipe[0]<=req_tag;for(k=1;k<7;k=k+1)tag_pipe[k]<=tag_pipe[k-1];end end',
       'assign rsp_valid=valid_pipe[6];assign rsp_is_fc=mode_pipe[6];assign rsp_tag=tag_pipe[6];',
       'logic [7:0] x0[0:35],f0[0:47],f1[0:47];integer r,c;',
       'always @(posedge clk)begin if(!rst_n)begin for(r=0;r<36;r=r+1)x0[r]<=0;',
       'for(r=0;r<48;r=r+1)begin f0[r]<=0;f1[r]<=0;end end else begin',
       'if(req_valid)begin if(req_is_fc)begin for(r=0;r<48;r=r+1)f0[r]<=fc_a[r][7:0];end',
       'else begin for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)x0[r*6+c]<=conv_tile[r][c][7:0];end end',
       'if(valid_pipe[0]&&mode_pipe[0])for(r=0;r<48;r=r+1)f1[r]<=f0[r];end end',
       "wire [6:0] key1={mode_pipe[1],tag_pipe[1][15],(mode_pipe[1]?tag_pipe[1][4]:1'b0),tag_pipe[1][3:0]};",
       "wire [6:0] key2={mode_pipe[2],tag_pipe[2][15],(mode_pipe[2]?tag_pipe[2][4]:1'b0),tag_pipe[2][3:0]};"]
    for lane in range(49):
        wa,wp,wc=aw[lane],pw[lane],bw[lane]
        s += [f'logic signed [{wa-1}:0] b1_{lane},a2_{lane};logic signed [{wp-1}:0] p3_{lane};']
        bterms=[]
        for j,coef in enumerate(BM[lane]):
            if coef:
                expr=sx(f"{{1'b0,x0[{j}]}}",9,wa) if wa!=9 else f"$signed({{1'b0,x0[{j}]}})"
                # Concatenations cannot be sliced/sign-extended by name; use a full-width unsigned cast.
                expr=f'$signed({{{wa-8}\'d0,x0[{j}]}})'
                bterms.append(('-'+expr) if coef<0 else expr)
        reset_product=f'p3_{lane}<=0;' if backend=='shift' else ''
        s += [f'always @(posedge clk)begin if(!rst_n)begin b1_{lane}<=0;a2_{lane}<=0;{reset_product}end else begin',
              f'if(valid_pipe[0]&&!mode_pipe[0])b1_{lane}<={total(bterms)};',
              f"if(valid_pipe[1])a2_{lane}<=mode_pipe[1]?"+(f"$signed({{{wa-8}'d0,f1[{lane}]}})" if lane<48 else "0")+f':b1_{lane};']
        if backend=='mul':
            s += ['end end',f'logic signed [{wc-1}:0] coefficient2_{lane};',
                  f'always @(posedge clk)begin if(!rst_n)coefficient2_{lane}<=0;else if(valid_pipe[1])begin case(key1)']
            s += [f"7'd{key}:coefficient2_{lane}<={literal(co,wc)};" for key,co in maps[lane].items() if co]
            s += [f"default:coefficient2_{lane}<={wc}'sd0;endcase end end",
                  f'always @(posedge clk)begin if(!rst_n)p3_{lane}<=0;else if(valid_pipe[2])p3_{lane}<={sx(f"a2_{lane}",wa,wp)}*{sx(f"coefficient2_{lane}",wc,wp)};end']
        else:
            s += ['if(valid_pipe[2])begin case(key2)']
            grouped={}
            for key,co in maps[lane].items():
                if co:grouped.setdefault(co,[]).append(key)
            for co,keys in grouped.items():
                if abs(co)&(abs(co)-1):raise ValueError('shift engine requires one PoT per temporal request')
                exp=abs(co).bit_length()-1
                expr='('+sx(f'a2_{lane}',wa,wp)+f' <<< {exp})'
                if co<0:expr='-'+expr
                s += [','.join("7'd"+str(k) for k in keys)+f':p3_{lane}<={expr};']
            s += [f"default:p3_{lane}<={wp}'sd0;endcase end end end"]
    for z in h:s.append(f'logic signed [{z["width"]-1}:0] {z["name"]};')
    for z in v:s.append(f'logic signed [{z["width"]-1}:0] {z["name"]};')
    for i,w in enumerate(f4w):s.append(f'logic signed [{w-1}:0] fg4_{i};')
    for i,w in enumerate(f5w):s.append(f'logic signed [{w-1}:0] fg5_{i};')
    s += ['always @(posedge clk)begin if(!rst_n)begin']
    s += [f'{z["name"]}<=0;' for z in h]
    s += [f'fg4_{i}<=0;' for i in range(16)]
    s += ['end else if(valid_pipe[3])begin if(!mode_pipe[3])begin']
    for z in h:
        terms=[('-' if co<0 else '')+sx(f'p3_{i}',pw[i],z['width']) for i,co in zip(z['ids'],z['coeff'])]
        s.append(z['name']+'<='+total(terms)+';')
    s += ['end else begin']
    for i,w in enumerate(f4w):s.append(f'fg4_{i}<='+total([sx(f'p3_{j}',pw[j],w) for j in range(i*3,i*3+3)])+';')
    s += ['end end end','always @(posedge clk)begin if(!rst_n)begin']
    s += [f'{z["name"]}<=0;' for z in v]
    s += [f'fg5_{i}<=0;' for i in range(4)]
    s += ['end else if(valid_pipe[4])begin if(!mode_pipe[4])begin']
    for z in v:
        terms=[('-' if co<0 else '')+sx(a['name'],a['width'],z['width']) for a,co in z['items']]
        s.append(z['name']+'<='+total(terms)+';')
    s += ['end else begin']
    for i,w in enumerate(f5w):s.append(f'fg5_{i}<='+total([sx(f'fg4_{j}',f4w[j],w) for j in range(i*4,i*4+4)])+';')
    s += ['end end end','always @(posedge clk)begin if(!rst_n)begin conv_y00<=0;conv_y01<=0;conv_y10<=0;conv_y11<=0;fc_sum<=0;end',
          'else if(valid_pipe[5])begin if(!mode_pipe[5])begin']
    for j,out in enumerate(('conv_y00','conv_y01','conv_y10','conv_y11')):
        terms=[]
        for bi,shift in enumerate((2,1,1,0)):
            z=next(z for z in v if z['name']==f'z_{bi}_{j}')
            terms.append('('+sx(z['name'],z['width'],32)+f' >>> {shift})')
        s.append(out+'<='+total(terms)+';')
    s += ['end else begin fc_sum<='+total([sx(f'fg5_{i}',f5w[i],32) for i in range(4)])+';end end end','endmodule']
    widths=dict(B_bits=aw,product_bits=pw,coefficient_bits=bw,
                horizontal_bits={z['name']:z['width'] for z in h},vertical_bits={z['name']:z['width'] for z in v},
                fc_group4_bits=f4w,fc_group5_bits=f5w,proof_scope='all independent input bytes 0..255')
    return '\n'.join(s)+'\n',widths

def generate_top(p):
    name=validate(p);source=(ROOT/'source_v25h/chip_pfdw_fc_v25h.sv').read_text()
    body=source[source.index('    localparam ST_STREAM'):source.rindex('endmodule')]
    start=body.index('    // Layer-specific scale restoration')
    end=body.index('    function automatic [2:0] add_mod7',start)
    helper=['    localparam integer C1_RESTORE_SHIFT=0,C2_RESTORE_SHIFT=0;',
            '    localparam integer FC_TWO_PASS='+str(int(name=='v25h'))+';']
    for fname,key in (('get_b1','b1'),('get_b2','b2'),('get_fcb','bfc')):
        helper += [f'function automatic signed [31:0] {fname}(input integer idx);begin case(idx)']
        helper += [f'{i}:{fname}={literal(int(x),32)};' for i,x in enumerate(p[key])]
        helper += [f'default:{fname}=0;endcase end endfunction']
    helper += ['function automatic [7:0] quant_u8(input signed [31:0] raw,input integer shift);',
               'reg signed [63:0] base,rem,half;begin base=$signed(raw)>>>shift;',
               'if(shift>0)begin rem=$signed(raw)-(base<<<shift);half=64\'sd1<<<(shift-1);',
               'if(rem>half||(rem==half&&base[0]))base=base+1;end',
               'if(base<0)quant_u8=0;else if(base>255)quant_u8=255;else quant_u8=base[7:0];end endfunction',
               f'function automatic signed [11:0] conv1_q(input signed [31:0] raw,bias32);begin conv1_q={{4\'d0,quant_u8(raw+bias32,{int(p["s1"])})}};end endfunction',
               f'function automatic signed [11:0] conv2_q(input signed [31:0] raw,bias32);begin conv2_q={{4\'d0,quant_u8(raw+bias32,{int(p["s2"])})}};end endfunction',
               'function automatic [7:0] max4_relu_a8(input signed [11:0] a,b,c,d);reg signed [11:0] m;begin',
               'm=a;if(b>m)m=b;if(c>m)m=c;if(d>m)m=d;max4_relu_a8=m[7:0];end endfunction',
               'logic signed [31:0] scores[0:3];integer score_clear;',
               'assign logits={scores[3],scores[2],scores[1],scores[0]};\n']
    body=body[:start]+'\n'.join(helper)+body[end:]
    body=body.replace('signed [19:0]','signed [31:0]').replace('signed [15:0] fc_term0_sum','signed [31:0] fc_term0_sum')
    body=body.replace('signed [15:0] rsp_fc_sum','signed [31:0] rsp_fc_sum')
    body=body.replace('signed [11:0] best_score','signed [31:0] best_score').replace('signed [11:0] fc_score_now','signed [31:0] fc_score_now')
    body=body.replace('signed [16:0] fc_class_sum','signed [31:0] fc_class_sum')
    body=body.replace('pfdw_pipe49_shift_engine_v25h u_engine','v25_dash_engine u_engine')
    for suffix in ('00','01','10','11'):body=body.replace(f'rsp_y{suffix}[19:0]',f'rsp_y{suffix}[31:0]')
    body=body.replace("fc_issue_count < 5'd20", "fc_issue_count < 5'd"+str(8 if name=='v25h' else 4))
    start=body.index('        // Exact reduced FC score datapath')
    end=body.index('\n    end\n\n    // ----',start)
    body=body[:start]+'        fc_class_sum = (FC_TWO_PASS ? fc_term0_sum : 32\'sd0) + rsp_fc_sum;\n        fc_score_now = fc_class_sum + get_fcb(rsp_fc_class);'+body[end:]
    body=body.replace("best_score <= -12'sd2048;","best_score <= 32'sh80000000;")
    body=body.replace("fc_term0_sum <= 16'sd0;","fc_term0_sum <= 32'sd0;")
    body=body.replace('            decision <= 0;','            for(score_clear=0;score_clear<4;score_clear=score_clear+1)scores[score_clear]<=0;\n            decision <= 0;')
    start=body.index('            if (req_valid && req_is_fc && state == ST_FC)')
    end=body.index('            // Conv1 response',start)
    progress='''            if(req_valid && req_is_fc && state==ST_FC)begin
                fc_issue_count<=fc_issue_count+1'b1;
                if(FC_TWO_PASS && !fc_issue_term)fc_issue_term<=1'b1;
                else begin fc_issue_term<=0;if(fc_issue_class<3)fc_issue_class<=fc_issue_class+1'b1;end
            end

'''
    body=body[:start]+progress+body[end:]
    body=body.replace("if (rsp_fc_term == 1'b0) begin", "if (FC_TWO_PASS && rsp_fc_term == 1'b0) begin")
    marker='                end else begin\n                    if (rsp_fc_class == 0) begin'
    if marker not in body:raise ValueError('frozen V25 controller FC pattern changed')
    body=body.replace(marker,'                end else begin\n                    scores[rsp_fc_class] <= fc_score_now;\n                    if (rsp_fc_class == 0) begin')
    body=body.replace('if (rsp_fc_class == 9)','if (rsp_fc_class == 3)').replace("decision <= 4'd9;","decision <= 2'd3;")
    header='''`timescale 1ps/1ps
// Derived from V25-H controller, commit 0d345f1. Continuous byte stream; one prime cycle after reset.
// DASH adaptation: four classes, train-derived scales, signed32 bias/score, RNE+U8 saturation.
module v25_dash_top(input logic clk,rst_n,input logic [7:0] data_in,
                   output logic [1:0] decision,output logic valid_out_6,output wire [127:0] logits);
'''
    return header+body+'endmodule\n'

def generate(p,out,backend='shift'):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    engine,widths=generate_engine(p,backend)
    (out/'v25_dash_engine.sv').write_text(engine)
    (out/'v25_dash_top.sv').write_text(generate_top(p))
    (out/'widths.json').write_text(json.dumps(widths,indent=2)+'\n')
    return out
