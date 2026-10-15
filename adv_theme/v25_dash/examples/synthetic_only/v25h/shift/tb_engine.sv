`timescale 1ps/1ps
module tb_engine;
reg clk=0,rst_n=0,req_valid=0,req_is_fc=0;reg [15:0] req_tag=0;
reg signed [8:0] tile[0:5][0:5],fa[0:47];wire rv,rf;wire [15:0] rt;
wire signed [31:0] y0,y1,y2,y3,fs;
v25_dash_engine dut(clk,rst_n,req_valid,req_is_fc,req_tag,tile,fa,rv,rf,rt,y0,y1,y2,y3,fs);
always #5 clk=~clk;
reg [7:0] xs[0:9215];reg [15:0] tags[0:191];reg fcs[0:191];reg [31:0] ys[0:767];
integer sent=0,received=0,r,c,j,cycle=0,issue_cycle[0:191];
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
 for(j=0;j<192;j=j+1)begin
  if(j%11==0)begin req_valid=0;@(negedge clk);end
  req_valid=1;req_tag=tags[j];req_is_fc=fcs[j];
  for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)tile[r][c]={1'b0,xs[j*48+r*6+c]};
  for(r=0;r<48;r=r+1)fa[r]={1'b0,xs[j*48+r]};
  @(negedge clk);
 end
 req_valid=0;repeat(10)@(negedge clk);
 if(received!=192)$fatal(1,"FAIL missing engine results");
 $display("PASS engine: 192 requests, all coefficient tags, bubbles, II=1, latency=6");$finish;
end
endmodule
