`timescale 1ns/1ps
`include "params.svh"
// Fixed v1.0 model. ROM files are emitted by train.py / integer.export.
// DIRECT=1 is the same integer CNN with an 84-product direct engine.
module dash_top #(parameter DIRECT=0)(
 input wire clk,input wire rst_n,input wire start,input wire [1:0] profile_id,
 input wire in_valid,input wire [7:0] pixel_in,output wire in_ready,
 output wire busy,output reg out_valid,input wire out_ready,
 output reg [1:0] class_id,output wire [95:0] logits,output reg profile_error);
 localparam IDLE=0,LOAD=1,ISSUE=2,WAIT_RESULT=3,OUTPUT=4;
 reg [2:0] state;reg [1:0] phase,profile,cls;
 reg [9:0] index_in;reg [3:0] oc,pr,pc;reg [2:0] ic,chunk;
 reg [7:0] input_mem[0:783],pool1_mem[0:863];reg [10:0] pool2_mem[0:191];
 reg signed [7:0] q1[0:149],q2[0:5399],qfc[0:575];
 reg signed [31:0] b1[0:5],b2[0:35],bfc[0:2];
 initial begin
  $readmemh("q1.mem",q1);$readmemh("q2.mem",q2);$readmemh("qfc.mem",qfc);
  $readmemh("b1.mem",b1);$readmemh("b2.mem",b2);$readmemh("bfc.mem",bfc);
 end
 reg signed [31:0] accum[0:3],facc,scores[0:2];
 assign logits={scores[2],scores[1],scores[0]};
 assign in_ready=state==LOAD;assign busy=state!=IDLE;
 reg [287:0] tile;reg [199:0] kernel;reg [439:0] fca;reg [319:0] fcw;
 wire valid=state==ISSUE,fc_mode=phase==2;
 wire rv,rf;wire [15:0] rt;wire [127:0] result_tile;wire signed [31:0] result_sum;
 integer r,c,k,ix,wi;
 always @* begin
  tile=0;kernel=0;fca=0;fcw=0;ix=0;wi=0;
  if(phase==0)begin
   for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)tile[(r*6+c)*8+:8]=input_mem[(2*pr+r)*28+2*pc+c];
   for(r=0;r<25;r=r+1)kernel[r*8+:8]=q1[oc*25+r];
  end else if(phase==1)begin
   for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)tile[(r*6+c)*8+:8]=pool1_mem[ic*144+(2*pr+r)*12+2*pc+c];
   for(r=0;r<25;r=r+1)kernel[r*8+:8]=q2[((profile*12+oc)*6+ic)*25+r];
  end else if(phase==2)begin
   for(k=0;k<40;k=k+1)begin
    ix=chunk*40+k;wi=cls*192+ix;
    if(ix<192)begin fca[k*11+:11]=pool2_mem[ix];fcw[k*8+:8]=qfc[wi];end
   end
  end
 end
 generate if(DIRECT)begin
  dash_engine_direct eng(clk,rst_n,valid,fc_mode,16'd0,tile,kernel,fca,fcw,rv,rf,rt,result_tile,result_sum);
 end else begin
  dash_engine_pfdw eng(clk,rst_n,valid,fc_mode,16'd0,tile,kernel,fca,fcw,rv,rf,rt,result_tile,result_sum);
 end endgenerate

 function automatic [10:0] quant_positive(input signed [31:0] x,input integer shift,input integer bits);
  reg [32:0] base,rem,half,limit;
  begin
   base=0;rem=0;half=0;limit=(33'd1<<bits)-1;
   if(x>0)begin
    base={1'b0,x}>>shift;
    if(shift>0)begin
     rem={1'b0,x}-(base<<shift);half=33'd1<<(shift-1);
     if(rem>half || (rem==half && base[0]))base=base+1;
    end
   end
   if(base>limit)base=limit;
   quant_positive=base[10:0];
  end
 endfunction
 integer j;
 reg signed [31:0] sums[0:3],mx,final_score,best;
 reg [1:0] winner;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;phase<=0;profile<=0;out_valid<=0;profile_error<=0;class_id<=0;
   index_in<=0;oc<=0;pr<=0;pc<=0;ic<=0;chunk<=0;cls<=0;facc<=0;
   for(j=0;j<4;j=j+1)accum[j]<=0;
   for(j=0;j<3;j=j+1)scores[j]<=0;
  end else case(state)
   IDLE: if(start)begin
    profile<=profile_id==3?0:profile_id;profile_error<=profile_id==3;
    index_in<=0;phase<=0;oc<=0;pr<=0;pc<=0;ic<=0;chunk<=0;cls<=0;facc<=0;
    for(j=0;j<4;j=j+1)accum[j]<=0;
    state<=LOAD;
   end
   LOAD: if(in_valid)begin
    input_mem[index_in]<=pixel_in;
    if(index_in==783)state<=ISSUE;else index_in<=index_in+1;
   end
   ISSUE:state<=WAIT_RESULT;
   WAIT_RESULT:if(rv)begin
    state<=ISSUE;
    if(phase<2)begin
     for(j=0;j<4;j=j+1)sums[j]=accum[j]+$signed(result_tile[j*32+:32]);
     if(phase==0 || ic==5)begin
      mx=sums[0];for(j=1;j<4;j=j+1)if(sums[j]>mx)mx=sums[j];
      // Bias is shared across the 2x2 tile; round/clip are monotone, so pool can precede them.
      if(phase==0)pool1_mem[oc*144+pr*12+pc]<=quant_positive(mx+b1[oc],`DASH_S1,8);
      else pool2_mem[oc*16+pr*4+pc]<=quant_positive(mx+b2[profile*12+oc],`DASH_S2,11);
      for(j=0;j<4;j=j+1)accum[j]<=0;
      ic<=0;
      if(pc==(phase==0?11:3))begin
       pc<=0;
       if(pr==(phase==0?11:3))begin
        pr<=0;
        if(oc==(phase==0?5:11))begin oc<=0;phase<=phase+1;end
        else oc<=oc+1;
       end else pr<=pr+1;
      end else pc<=pc+1;
     end else begin
      for(j=0;j<4;j=j+1)accum[j]<=sums[j];ic<=ic+1;
     end
    end else begin
     if(chunk==4)begin
      final_score=facc+result_sum+bfc[cls];scores[cls]<=final_score;facc<=0;chunk<=0;
      if(cls==2)begin
       best=scores[0];winner=0;
       if(scores[1]>best)begin best=scores[1];winner=1;end
       if(final_score>best)winner=2;
       class_id<=winner;out_valid<=1;state<=OUTPUT;
      end else cls<=cls+1;
     end else begin facc<=facc+result_sum;chunk<=chunk+1;end
    end
   end
   OUTPUT:if(out_ready)begin out_valid<=0;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
endmodule
