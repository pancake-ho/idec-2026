`timescale 1ps/1ps
module tb_top;
reg clk=0,rst_n=0;reg [7:0] data_in=0;wire [1:0] decision;wire valid_out_6;wire [127:0] logits;
v25_dash_top dut(clk,rst_n,data_in,decision,valid_out_6,logits);
always #5 clk=~clk;
reg [7:0] pixels[0:5487],p1[0:2015],p2[0:335];
reg [31:0] scores[0:27];reg [1:0] decisions[0:6];
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
 for(n=0;n<7;n=n+1)begin
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
