`timescale 1ns/1ps
module tb_top;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,iv=0,oready=0;reg [1:0] profile=0;reg [7:0] pixel=0;
 wire ready0,ready1,busy0,busy1,v0,v1,e0,e1;wire [1:0] cl0,cl1;wire [95:0] l0,l1;
 dash_top #(.DIRECT(0)) p(clk,rst_n,start,profile,iv,pixel,ready0,busy0,v0,oready,cl0,l0,e0);
 dash_top #(.DIRECT(1)) d(clk,rst_n,start,profile,iv,pixel,ready1,busy1,v1,oready,cl1,l1,e1);
 reg [7:0] pixels[0:783];reg [31:0] wanted[0:2];integer n,i,waitcycles,j,cycle=0,started;
 reg signed [31:0] best;reg [1:0] winner;reg [95:0] held;
 always @(posedge clk)cycle=cycle+1;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(n=0;n<4;n=n+1)begin
   $readmemh($sformatf("input_%0d.mem",n),pixels);$readmemh($sformatf("expected_%0d.mem",n),wanted);
   @(negedge clk);start=1;profile=n;started=cycle;
   @(negedge clk);start=0;
   for(i=0;i<784;i=i+1)begin
    if(!ready0 || !ready1)$fatal(1,"input readiness");
    if(i%37==0)begin iv=0;@(negedge clk);end
    iv=1;pixel=pixels[i];@(negedge clk);
   end
   iv=0;profile=3-n; // Changing external selection during inference must have no effect.
   waitcycles=0;
   while(!v0 && waitcycles<30000)begin @(negedge clk);waitcycles=waitcycles+1;end
   if(!v0 || !v1)$fatal(1,"timeout or valid mismatch");
   if(l0!=={wanted[2],wanted[1],wanted[0]} || l1!==l0)$fatal(1,"logits case %d got %h expected %h",n,l0,{wanted[2],wanted[1],wanted[0]});
   best=$signed(wanted[0]);winner=0;
   for(j=1;j<3;j=j+1)if($signed(wanted[j])>best)begin best=$signed(wanted[j]);winner=j;end
   if(cl0!==winner || cl1!==winner || e0!==(n==3) || e1!==e0)$fatal(1,"class/profile");
   held=l0;repeat(4)begin @(negedge clk);if(!v0 || l0!==held || !v1 || l1!==held)$fatal(1,"output backpressure");end
   $display("PASS top case=%0d class=%0d cycles_start_to_output_plus_hold=%0d",n,cl0,cycle-started);
   oready=1;@(negedge clk);oready=0;
  end
  $display("PASS top four images, profiles, stalled input/output, exact logits");$finish;
 end
endmodule
