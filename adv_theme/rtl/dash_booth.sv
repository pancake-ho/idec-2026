`timescale 1ns/1ps
// V18A correction-vector radix-4 method, generalized balanced tree for BW=6..12.
module dash_booth #(parameter AW=12, BW=8)(
 input wire signed [AW-1:0] a, input wire signed [BW-1:0] b,
 output wire signed [AW+BW-1:0] p);
 localparam NG=(BW+1)/2, CW=AW+BW+2, NP=2**$clog2(NG);
 reg [2*NG:0] y;
 reg signed [CW-1:0] ae,base;
 reg signed [CW-1:0] pp[0:NG-1];
 reg [CW-1:0] corr;
 reg [2:0] code;
 integer i;
 always @* begin
  y=0;y[0]=0;corr=0;ae={{(CW-AW){a[AW-1]}},a};base=0;code=0;
  for(i=0;i<BW;i=i+1)y[i+1]=b[i];
  for(i=BW;i<2*NG;i=i+1)y[i+1]=b[BW-1];
  for(i=0;i<NG;i=i+1)begin
   code=y[2*i+:3];
   case(code)
    3'b001,3'b010,3'b101,3'b110:base=ae;
    3'b011,3'b100:base=ae<<<1;
    default:base=0;
   endcase
   if(code==3'b100 || code==3'b101 || code==3'b110)begin pp[i]=(~base)<<<(2*i);corr[2*i]=1;end
   else pp[i]=base<<<(2*i);
  end
 end
 wire signed [CW-1:0] tree[0:2*NP-2];
 genvar k;
 generate for(k=0;k<NP;k=k+1)begin
  if(k<NG)assign tree[NP-1+k]=pp[k];else assign tree[NP-1+k]=0;
 end
 for(k=0;k<NP-1;k=k+1)begin assign tree[k]=tree[2*k+1]+tree[2*k+2];end endgenerate
 wire signed [CW-1:0] total=tree[0]+$signed(corr);
 assign p=total[AW+BW-1:0];
endmodule
