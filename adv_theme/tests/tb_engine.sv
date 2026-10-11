`timescale 1ns/1ps
module tb_engine;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,valid=0,fc=0;reg [15:0] tag=0;reg [287:0] tile=0;reg [199:0] kernel=0;
 reg [439:0] fca=0;reg [319:0] fcw=0;
 wire v0,v1,f0,f1;wire [15:0] t0,t1;wire [127:0] o0,o1;wire signed [31:0] s0,s1;
 dash_engine_pfdw p(clk,rst_n,valid,fc,tag,tile,kernel,fca,fcw,v0,f0,t0,o0,s0);
 dash_engine_direct d(clk,rst_n,valid,fc,tag,tile,kernel,fca,fcw,v1,f1,t1,o1,s1);
 reg [127:0] expected[0:255];reg [31:0] sums[0:255];integer launch[0:255],mode[0:255];
 integer fd,n,idx,m,cyc=0,received=0,j;reg [127:0] want;reg [31:0] sum;
 always @(posedge clk)begin
  cyc=cyc+1;if(valid)launch[tag]=cyc;
  #1;
  if(rst_n && v0!==v1)$fatal(1,"valid mismatch");
  if(v0)begin
   if(t0!==t1 || f0!==f1 || f0!==mode[t0][0])$fatal(1,"tag/mode mismatch");
   if(cyc-launch[t0]!=6)$fatal(1,"latency mismatch");
   if(f0)begin if(s0!==sums[t0] || s1!==sums[t0])$fatal(1,"FC mismatch tag %d: %d %d %d",t0,s0,s1,$signed(sums[t0]));end
   else if(o0!==expected[t0] || o1!==expected[t0])$fatal(1,"Conv mismatch %d",t0);
   received=received+1;
  end
 end
 initial begin
  fd=$fopen("engine_vectors.txt","r");if(!fd)$fatal(1,"missing vectors");
  repeat(3)@(negedge clk);rst_n=1;
  for(j=0;j<256;j=j+1)begin
   @(negedge clk);
   if(j%5==0)begin valid=0;@(negedge clk);end
   n=$fscanf(fd,"%d %d %h %h %h %h %h %h\n",idx,m,tile,kernel,fca,fcw,want,sum);
   if(n!=8)$fatal(1,"bad vector");tag=idx;fc=m;valid=1;expected[idx]=want;sums[idx]=sum;mode[idx]=m;
  end
  @(negedge clk);valid=0;repeat(12)@(negedge clk);
  if(received!=256)$fatal(1,"response count %d",received);
  $display("PASS engine 256 cases, direct=PFDW, II=1, latency=6, bubbles checked");$finish;
 end
endmodule
