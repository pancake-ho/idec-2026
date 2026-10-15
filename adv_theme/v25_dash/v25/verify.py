"""Actual Icarus runs against exported integer scores and intermediate feature maps."""
import json
from pathlib import Path
import shutil
import subprocess
import numpy as np
from .transforms import BM,inverse
from .integer import validate,infer,infer_spatial
from .hardware import generate
from .util import write_json,sha256

def hexfile(path,values,bits):
    Path(path).write_text('\n'.join(format(int(x)&((1<<bits)-1),'0'+str((bits+3)//4)+'x') for x in np.asarray(values).flat)+'\n')

def compile_run(folder,top,iverilog,vvp,ivl_base=None):
    folder=Path(folder).resolve()
    iv=shutil.which(iverilog) or str(Path(iverilog).resolve())
    vp=shutil.which(vvp) or str(Path(vvp).resolve())
    cmd=[iv]
    if ivl_base:cmd+=['-B',str(Path(ivl_base).resolve())]
    cmd+=['-g2012','-s',top,'-o','simulation.vvp']+[str(p.name) for p in sorted(folder.glob('*.sv'))]
    c=subprocess.run(cmd,cwd=folder,text=True,capture_output=True,timeout=120)
    (folder/'compile.log').write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError('RTL compile failed: '+str(folder/'compile.log'))
    # Width mismatch is a real contract failure; Icarus constant-select notices are harmless.
    if 'expects' in c.stderr and 'bits, got' in c.stderr:raise RuntimeError('RTL port-width mismatch')
    r=subprocess.run([vp,'simulation.vvp'],cwd=folder,text=True,capture_output=True,timeout=120)
    (folder/'simulation.log').write_text(r.stdout+r.stderr)
    if r.returncode or 'PASS' not in r.stdout or 'FAIL' in r.stdout:raise RuntimeError('RTL mismatch: '+str(folder/'simulation.log'))
    print(r.stdout.strip(),flush=True)
    return r.stdout

def engine_vectors(p,folder,seed=2026,count=192):
    rng=np.random.default_rng(seed);tags=[];isfc=[];inputs=[];expected=[]
    # All eight convolution kernels and every FC temporal term appear repeatedly.
    rows=[(0,o*4,p['q1_td'][o,0]) for o in range(2)]
    rows +=[(0,0x8000+o*4+i,p['q2_td'][o,i]) for o in range(3) for i in range(2)]
    rows +=[(1,t*16+c,p['fc_terms'][c,:,t]) for c in range(4) for t in range(p['fc_terms'].shape[-1])]
    for k in range(count):
        fc,tag,co=rows[k%len(rows)];x=rng.integers(0,256,48,dtype=np.int64)
        if k<len(rows):x[:]=255 if k%2 else 0
        y=np.array([np.dot(x,co),0,0,0]) if fc else inverse((BM@x[:36])*co)
        tags.append(tag);isfc.append(fc);inputs.append(x);expected.append(y)
    for name,arr,bits in [('engine_x.hex',inputs,8),('engine_tag.hex',tags,16),('engine_fc.hex',isfc,1),('engine_y.hex',expected,32)]:hexfile(folder/name,arr,bits)
    text=f'''`timescale 1ps/1ps
module tb_engine;
reg clk=0,rst_n=0,req_valid=0,req_is_fc=0;reg [15:0] req_tag=0;
reg signed [8:0] tile[0:5][0:5],fa[0:47];wire rv,rf;wire [15:0] rt;
wire signed [31:0] y0,y1,y2,y3,fs;
v25_dash_engine dut(clk,rst_n,req_valid,req_is_fc,req_tag,tile,fa,rv,rf,rt,y0,y1,y2,y3,fs);
always #5 clk=~clk;
reg [7:0] xs[0:{count*48-1}];reg [15:0] tags[0:{count-1}];reg fcs[0:{count-1}];reg [31:0] ys[0:{count*4-1}];
integer sent=0,received=0,r,c,j,cycle=0,issue_cycle[0:{count-1}];
always @(posedge clk)begin
 cycle=cycle+1;
 if(rst_n && req_valid)begin issue_cycle[sent]=cycle;sent=sent+1;end
 #1;
 if(rst_n && rv)begin
  if(received>=sent || rt!==tags[received] || rf!==fcs[received])$fatal(1,"FAIL engine tag/order");
  if(cycle-issue_cycle[received]!=6)$fatal(1,"FAIL engine latency");
  if(rf)begin if(fs!==ys[received*4])$fatal(1,"FAIL FC engine case=%0d got=%0d expected=%0d",received,fs,$signed(ys[received*4]));end
  else if(y0!==ys[received*4]||y1!==ys[received*4+1]||y2!==ys[received*4+2]||y3!==ys[received*4+3])
   $fatal(1,"FAIL Conv engine case=%0d got=%0d,%0d,%0d,%0d expected=%0d,%0d,%0d,%0d",received,y0,y1,y2,y3,$signed(ys[received*4]),$signed(ys[received*4+1]),$signed(ys[received*4+2]),$signed(ys[received*4+3]));
  received=received+1;
 end
end
initial begin
 $readmemh("engine_x.hex",xs);$readmemh("engine_tag.hex",tags);$readmemh("engine_fc.hex",fcs);$readmemh("engine_y.hex",ys);
 repeat(3)@(negedge clk);rst_n=1;
 for(j=0;j<{count};j=j+1)begin
  if(j%11==0)begin req_valid=0;@(negedge clk);end
  req_valid=1;req_tag=tags[j];req_is_fc=fcs[j];
  for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)tile[r][c]={{1'b0,xs[j*48+r*6+c]}};
  for(r=0;r<48;r=r+1)fa[r]={{1'b0,xs[j*48+r]}};
  @(negedge clk);
 end
 req_valid=0;repeat(10)@(negedge clk);
 if(received!={count})$fatal(1,"FAIL missing engine results");
 $display("PASS engine: {count} requests, all coefficient tags, bubbles, II=1, latency=6");$finish;
end
endmodule
'''
    (folder/'tb_engine.sv').write_text(text)

def top_vectors(x,p,folder):
    golden=infer(x,p);count=len(x)
    for name,arr,bits in [('pixels.hex',x,8),('scores.hex',golden['scores'],32),('pool1.hex',golden['pool1'],8),('pool2.hex',golden['pool2'],8),('decision.hex',golden['decision'],2)]:hexfile(folder/name,arr,bits)
    text=f'''`timescale 1ps/1ps
module tb_top;
reg clk=0,rst_n=0;reg [7:0] data_in=0;wire [1:0] decision;wire valid_out_6;wire [127:0] logits;
v25_dash_top dut(clk,rst_n,data_in,decision,valid_out_6,logits);
always #5 clk=~clk;
reg [7:0] pixels[0:{count*784-1}],p1[0:{count*288-1}],p2[0:{count*48-1}];
reg [31:0] scores[0:{count*4-1}];reg [1:0] decisions[0:{count-1}];
integer n,j,c,r,col,cycles;
always @(posedge clk)begin
 if(rst_n)begin
  if(dut.c1_wb_valid)begin
   r=dut.c1_commit_count/24;c=dut.c1_wb_oc;col=dut.c1_wb_pc;
   if(dut.max4_relu_a8(dut.c1_wb_q00,dut.c1_wb_q01,dut.c1_wb_q10,dut.c1_wb_q11)!==p1[n*288+c*144+r*12+col])
    $fatal(1,"FAIL pool1 case=%0d channel=%0d row=%0d col=%0d",n,c,r,col);
  end
 end
end
task reset_patch;begin rst_n=0;data_in=0;repeat(3)@(negedge clk);rst_n=1;@(negedge clk);end endtask
initial begin
 $readmemh("pixels.hex",pixels);$readmemh("scores.hex",scores);$readmemh("pool1.hex",p1);$readmemh("pool2.hex",p2);$readmemh("decision.hex",decisions);
 for(n=0;n<{count};n=n+1)begin
  reset_patch();
  for(j=0;j<784;j=j+1)begin data_in=pixels[n*784+j];@(negedge clk);end
  data_in=0;cycles=784;
  while(!valid_out_6 && cycles<2000)begin @(negedge clk);cycles=cycles+1;end
  if(!valid_out_6)$fatal(1,"FAIL top timeout");
  for(c=0;c<4;c=c+1)if(logits[c*32+:32]!==scores[n*4+c])$fatal(1,"FAIL score case=%0d class=%0d got=%0d expected=%0d",n,c,$signed(logits[c*32+:32]),$signed(scores[n*4+c]));
  if(decision!==decisions[n])$fatal(1,"FAIL decision");
  for(c=0;c<3;c=c+1)for(r=0;r<4;r=r+1)for(col=0;col<4;col=col+1)
   if(dut.fmap2[c][r][col]!==p2[n*48+c*16+r*4+col])$fatal(1,"FAIL pool2");
  if(dut.c1_commit_count!=288||dut.c2_commit_count!=48)$fatal(1,"FAIL commit count");
  $display("PASS top case=%0d class=%0d input_start_to_result_cycles=%0d",n,decision,cycles);
  repeat(3)begin @(negedge clk);if(valid_out_6)$fatal(1,"FAIL repeated valid");end
 end
 // Interrupt a fresh patch, reset, then reproduce case zero to catch stale ring/valid state.
 n=0;reset_patch();for(j=0;j<97;j=j+1)begin data_in=pixels[j];@(negedge clk);end
 reset_patch();for(j=0;j<784;j=j+1)begin data_in=pixels[j];@(negedge clk);end
 cycles=784;while(!valid_out_6&&cycles<2000)begin @(negedge clk);cycles=cycles+1;end
 if(!valid_out_6||decision!==decisions[0])$fatal(1,"FAIL mid-patch reset");
 for(c=0;c<4;c=c+1)if(logits[c*32+:32]!==scores[c])$fatal(1,"FAIL reset score");
 $display("PASS top: all four scores, both pooled maps, U8 extremes, repeat reset, mid-patch reset");$finish;
end
endmodule
'''
    (folder/'tb_top.sv').write_text(text)

def verify(p,x,out,iverilog='iverilog',vvp='vvp',ivl_base=None):
    name=validate(p);out=Path(out).resolve();out.mkdir(parents=True,exist_ok=True)
    # Validation representatives plus boundary patterns. Never consult test data here.
    x=np.asarray(x,np.uint8)
    checker=np.indices((28,28)).sum(0)%2*255
    vectors=np.concatenate((x,np.zeros((1,28,28),np.uint8),np.full((1,28,28),255,np.uint8),checker[None].astype(np.uint8)))
    a=infer(vectors,p)
    b=infer(vectors,p,'shift') if name=='v25h' else infer_spatial(vectors,p)
    for key in a:
        if not np.array_equal(a[key],b[key]):raise AssertionError('independent integer backend mismatch: '+key)
    backends=('mul','shift') if name=='v25h' else ('mul',)
    logs={}
    for backend in backends:
        folder=generate(p,out/backend,backend)
        engine_vectors(p,folder);top_vectors(vectors,p,folder)
        logs[backend]=dict(engine=compile_run(folder,'tb_engine',iverilog,vvp,ivl_base),
                           top=compile_run(folder,'tb_top',iverilog,vvp,ivl_base),
                           rtl_sha256={f.name:sha256(f) for f in folder.glob('v25_*.sv')})
    report=dict(status='PASS_EXPORTED_INTEGER_AND_ACTUAL_RTL',mode=name,backend_equivalence=True,
                validation_and_edge_cases=len(vectors),source='validation + synthetic U8 patterns',
                protocol='one prime cycle after reset; continuous 784 bytes; no input stalls; per-patch reset',
                ppa_status='NOT_MEASURED',logs=logs)
    write_json(out/'verification.json',report);return report
