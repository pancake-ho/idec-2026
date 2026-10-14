`timescale 1ns/1ps
module tb_top;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,iv=0,oready=0;reg [1:0] profile=0;reg [7:0] pixel=0;
 wire ready0,ready1,busy0,busy1,v0,v1,e0,e1;wire [1:0] cl0,cl1;wire [127:0] l0,l1;
 dash_top #(.DIRECT(0)) p(clk,rst_n,start,profile,iv,pixel,ready0,busy0,v0,oready,cl0,l0,e0);
 dash_top #(.DIRECT(1)) d(clk,rst_n,start,profile,iv,pixel,ready1,busy1,v1,oready,cl1,l1,e1);
 reg [7:0] pixels[0:783];reg [31:0] wanted[0:3];integer n,i,waitcycles,j,cycle=0,started,caseid;
 reg signed [31:0] best;reg [1:0] winner;reg [127:0] held;
 always @(posedge clk)cycle=cycle+1;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(n=0;n<5;n=n+1)begin
   caseid=n%4;
   if(n==4)begin
    // Abort a partial patch and ensure both controllers recover cleanly.
    @(negedge clk);start=1;profile=1;
    @(negedge clk);start=0;iv=1;pixel=123;
    repeat(11)@(negedge clk);rst_n=0;iv=0;
    repeat(2)@(negedge clk);
    if(v0 || v1 || busy0 || busy1)$fatal(1,"mid-patch reset recovery");
    rst_n=1;
   end
   $readmemh($sformatf("input_%0d.mem",caseid),pixels);$readmemh($sformatf("expected_%0d.mem",caseid),wanted);
   @(negedge clk);start=1;profile=caseid;started=cycle;
   @(negedge clk);start=0;
   for(i=0;i<784;i=i+1)begin
    if(!ready0 || !ready1)$fatal(1,"input readiness");
    if(i%37==0)begin iv=0;@(negedge clk);end
    iv=1;pixel=pixels[i];@(negedge clk);
   end
   iv=0;profile=3-caseid;
   waitcycles=0;
   while(!v0 && waitcycles<30000)begin @(negedge clk);waitcycles=waitcycles+1;end
   if(!v0 || !v1)$fatal(1,"timeout or valid mismatch");
   if(l0!=={wanted[3],wanted[2],wanted[1],wanted[0]} || l1!==l0)$fatal(1,"four logits mismatch case %d",caseid);
   best=$signed(wanted[0]);winner=0;
   for(j=1;j<4;j=j+1)if($signed(wanted[j])>best)begin best=$signed(wanted[j]);winner=j;end
   if(cl0!==winner || cl1!==winner || e0!==(caseid>1) || e1!==e0)$fatal(1,"class/profile");
   held=l0;repeat(4)begin @(negedge clk);if(!v0 || l0!==held || !v1 || l1!==held)$fatal(1,"output hold");end
   $display("PASS top case=%0d class=%0d cycles_start_to_output_plus_hold=%0d",caseid,cl0,cycle-started);
   oready=1;@(negedge clk);oready=0;
  end
  $display("PASS AVC4 top: five runs, four logits, profile fallback, input/output stalls, mid-patch reset");$finish;
 end
endmodule
