`timescale 1ps/1ps
// V25-derived 49-lane coefficient-specific shared pipeline; generated for DASH.
// mode=v25h, backend=shift; P0 request -> P6 response, II=1.
module v25_dash_engine(input logic clk,rst_n,req_valid,req_is_fc, input logic [15:0] req_tag,
input wire signed [8:0] conv_tile[0:5][0:5], input wire signed [8:0] fc_a[0:47],
output logic rsp_valid,rsp_is_fc, output logic [15:0] rsp_tag,
output logic signed [31:0] conv_y00,conv_y01,conv_y10,conv_y11,fc_sum);
logic [6:0] valid_pipe,mode_pipe; logic [15:0] tag_pipe[0:6]; integer k;
always @(posedge clk) begin if(!rst_n)begin valid_pipe<=0;mode_pipe<=0;for(k=0;k<7;k=k+1)tag_pipe[k]<=0;end
else begin valid_pipe<={valid_pipe[5:0],req_valid};mode_pipe<={mode_pipe[5:0],req_is_fc};
tag_pipe[0]<=req_tag;for(k=1;k<7;k=k+1)tag_pipe[k]<=tag_pipe[k-1];end end
assign rsp_valid=valid_pipe[6];assign rsp_is_fc=mode_pipe[6];assign rsp_tag=tag_pipe[6];
logic [7:0] x0[0:35],f0[0:47],f1[0:47];integer r,c;
always @(posedge clk)begin if(!rst_n)begin for(r=0;r<36;r=r+1)x0[r]<=0;
for(r=0;r<48;r=r+1)begin f0[r]<=0;f1[r]<=0;end end else begin
if(req_valid)begin if(req_is_fc)begin for(r=0;r<48;r=r+1)f0[r]<=fc_a[r][7:0];end
else begin for(r=0;r<6;r=r+1)for(c=0;c<6;c=c+1)x0[r*6+c]<=conv_tile[r][c][7:0];end end
if(valid_pipe[0]&&mode_pipe[0])for(r=0;r<48;r=r+1)f1[r]<=f0[r];end end
wire [6:0] key1={mode_pipe[1],tag_pipe[1][15],(mode_pipe[1]?tag_pipe[1][4]:1'b0),tag_pipe[1][3:0]};
wire [6:0] key2={mode_pipe[2],tag_pipe[2][15],(mode_pipe[2]?tag_pipe[2][4]:1'b0),tag_pipe[2][3:0]};
logic signed [9:0] b1_0,a2_0;logic signed [15:0] p3_0;
always @(posedge clk)begin if(!rst_n)begin b1_0<=0;a2_0<=0;p3_0<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_0<=(($signed({2'd0,x0[0]}) + -$signed({2'd0,x0[2]})) + (-$signed({2'd0,x0[12]}) + $signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_0<=mode_pipe[1]?$signed({2'd0,f1[0]}):b1_0;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4,7'd33:p3_0<=-($signed({{6{a2_0[9]}},a2_0}) <<< 5);
7'd37,7'd40:p3_0<=($signed({{6{a2_0[9]}},a2_0}) <<< 5);
7'd41:p3_0<=($signed({{6{a2_0[9]}},a2_0}) <<< 6);
7'd64:p3_0<=($signed({{6{a2_0[9]}},a2_0}) <<< 2);
7'd65,7'd67:p3_0<=-($signed({{6{a2_0[9]}},a2_0}) <<< 4);
7'd66:p3_0<=-($signed({{6{a2_0[9]}},a2_0}) <<< 3);
7'd82:p3_0<=-($signed({{6{a2_0[9]}},a2_0}) <<< 2);
default:p3_0<=16'sd0;endcase end end end
logic signed [9:0] b1_1,a2_1;logic signed [15:0] p3_1;
always @(posedge clk)begin if(!rst_n)begin b1_1<=0;a2_1<=0;p3_1<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_1<=(($signed({2'd0,x0[1]}) + $signed({2'd0,x0[2]})) + (-$signed({2'd0,x0[13]}) + -$signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_1<=mode_pipe[1]?$signed({2'd0,f1[1]}):b1_1;
if(valid_pipe[2])begin case(key2)
7'd0:p3_1<=-($signed({{6{a2_1[9]}},a2_1}) <<< 4);
7'd4,7'd65:p3_1<=-($signed({{6{a2_1[9]}},a2_1}) <<< 2);
7'd32,7'd40:p3_1<=-($signed({{6{a2_1[9]}},a2_1}) <<< 3);
7'd33:p3_1<=-($signed({{6{a2_1[9]}},a2_1}) <<< 6);
7'd36,7'd64,7'd67:p3_1<=($signed({{6{a2_1[9]}},a2_1}) <<< 3);
7'd37:p3_1<=($signed({{6{a2_1[9]}},a2_1}) <<< 5);
7'd41:p3_1<=($signed({{6{a2_1[9]}},a2_1}) <<< 4);
7'd80,7'd66:p3_1<=($signed({{6{a2_1[9]}},a2_1}) <<< 2);
7'd81:p3_1<=-($signed({{6{a2_1[9]}},a2_1}) <<< 1);
7'd83:p3_1<=($signed({{6{a2_1[9]}},a2_1}) <<< 1);
default:p3_1<=16'sd0;endcase end end end
logic signed [9:0] b1_2,a2_2;logic signed [15:0] p3_2;
always @(posedge clk)begin if(!rst_n)begin b1_2<=0;a2_2<=0;p3_2<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_2<=((-$signed({2'd0,x0[1]}) + $signed({2'd0,x0[2]})) + ($signed({2'd0,x0[13]}) + -$signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_2<=mode_pipe[1]?$signed({2'd0,f1[2]}):b1_2;
if(valid_pipe[2])begin case(key2)
7'd0,7'd67:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 2);
7'd4,7'd32:p3_2<=-($signed({{6{a2_2[9]}},a2_2}) <<< 5);
7'd33,7'd64,7'd65:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 3);
7'd36,7'd40:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 5);
7'd37:p3_2<=-($signed({{6{a2_2[9]}},a2_2}) <<< 3);
7'd41:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 6);
7'd80:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 0);
7'd81,7'd83:p3_2<=($signed({{6{a2_2[9]}},a2_2}) <<< 1);
7'd66:p3_2<=-($signed({{6{a2_2[9]}},a2_2}) <<< 2);
default:p3_2<=16'sd0;endcase end end end
logic signed [9:0] b1_3,a2_3;logic signed [14:0] p3_3;
always @(posedge clk)begin if(!rst_n)begin b1_3<=0;a2_3<=0;p3_3<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_3<=(($signed({2'd0,x0[1]}) + -$signed({2'd0,x0[3]})) + (-$signed({2'd0,x0[13]}) + $signed({2'd0,x0[15]})));
if(valid_pipe[1])a2_3<=mode_pipe[1]?$signed({2'd0,f1[3]}):b1_3;
if(valid_pipe[2])begin case(key2)
7'd0,7'd66:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 4);
7'd4:p3_3<=-($signed({{5{a2_3[9]}},a2_3}) <<< 4);
7'd32:p3_3<=-($signed({{5{a2_3[9]}},a2_3}) <<< 5);
7'd36:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 5);
7'd37,7'd40:p3_3<=-($signed({{5{a2_3[9]}},a2_3}) <<< 3);
7'd41,7'd65,7'd67:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 3);
7'd64:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 2);
7'd80,7'd81:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 1);
7'd82:p3_3<=($signed({{5{a2_3[9]}},a2_3}) <<< 0);
default:p3_3<=15'sd0;endcase end end end
logic signed [9:0] b1_4,a2_4;logic signed [15:0] p3_4;
always @(posedge clk)begin if(!rst_n)begin b1_4<=0;a2_4<=0;p3_4<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_4<=(($signed({2'd0,x0[6]}) + -$signed({2'd0,x0[8]})) + ($signed({2'd0,x0[12]}) + -$signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_4<=mode_pipe[1]?$signed({2'd0,f1[4]}):b1_4;
if(valid_pipe[2])begin case(key2)
7'd0,7'd82:p3_4<=-($signed({{6{a2_4[9]}},a2_4}) <<< 1);
7'd4,7'd37:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 3);
7'd32:p3_4<=-($signed({{6{a2_4[9]}},a2_4}) <<< 5);
7'd33,7'd40,7'd67:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 4);
7'd36:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 5);
7'd41:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 6);
7'd64:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 2);
7'd80:p3_4<=($signed({{6{a2_4[9]}},a2_4}) <<< 1);
7'd66:p3_4<=-($signed({{6{a2_4[9]}},a2_4}) <<< 4);
7'd83:p3_4<=-($signed({{6{a2_4[9]}},a2_4}) <<< 0);
default:p3_4<=16'sd0;endcase end end end
logic signed [10:0] b1_5,a2_5;logic signed [15:0] p3_5;
always @(posedge clk)begin if(!rst_n)begin b1_5<=0;a2_5<=0;p3_5<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_5<=(($signed({3'd0,x0[7]}) + $signed({3'd0,x0[8]})) + ($signed({3'd0,x0[13]}) + $signed({3'd0,x0[14]})));
if(valid_pipe[1])a2_5<=mode_pipe[1]?$signed({3'd0,f1[5]}):b1_5;
if(valid_pipe[2])begin case(key2)
7'd0,7'd36,7'd37,7'd40:p3_5<=-($signed({{5{a2_5[10]}},a2_5}) <<< 4);
7'd4,7'd65:p3_5<=($signed({{5{a2_5[10]}},a2_5}) <<< 4);
7'd32:p3_5<=($signed({{5{a2_5[10]}},a2_5}) <<< 2);
7'd33:p3_5<=($signed({{5{a2_5[10]}},a2_5}) <<< 3);
7'd41:p3_5<=($signed({{5{a2_5[10]}},a2_5}) <<< 5);
7'd64:p3_5<=-($signed({{5{a2_5[10]}},a2_5}) <<< 3);
7'd81,7'd83:p3_5<=-($signed({{5{a2_5[10]}},a2_5}) <<< 0);
7'd66:p3_5<=-($signed({{5{a2_5[10]}},a2_5}) <<< 2);
7'd82,7'd67:p3_5<=-($signed({{5{a2_5[10]}},a2_5}) <<< 1);
default:p3_5<=16'sd0;endcase end end end
logic signed [9:0] b1_6,a2_6;logic signed [14:0] p3_6;
always @(posedge clk)begin if(!rst_n)begin b1_6<=0;a2_6<=0;p3_6<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_6<=((-$signed({2'd0,x0[7]}) + $signed({2'd0,x0[8]})) + (-$signed({2'd0,x0[13]}) + $signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_6<=mode_pipe[1]?$signed({2'd0,f1[6]}):b1_6;
if(valid_pipe[2])begin case(key2)
7'd0:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 2);
7'd4:p3_6<=-($signed({{5{a2_6[9]}},a2_6}) <<< 2);
7'd32:p3_6<=-($signed({{5{a2_6[9]}},a2_6}) <<< 5);
7'd33,7'd37,7'd41:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 5);
7'd36,7'd65:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 3);
7'd40:p3_6<=-($signed({{5{a2_6[9]}},a2_6}) <<< 4);
7'd64:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 4);
7'd80:p3_6<=-($signed({{5{a2_6[9]}},a2_6}) <<< 1);
7'd81,7'd66,7'd67:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 1);
7'd82:p3_6<=($signed({{5{a2_6[9]}},a2_6}) <<< 0);
default:p3_6<=15'sd0;endcase end end end
logic signed [9:0] b1_7,a2_7;logic signed [15:0] p3_7;
always @(posedge clk)begin if(!rst_n)begin b1_7<=0;a2_7<=0;p3_7<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_7<=(($signed({2'd0,x0[7]}) + -$signed({2'd0,x0[9]})) + ($signed({2'd0,x0[13]}) + -$signed({2'd0,x0[15]})));
if(valid_pipe[1])a2_7<=mode_pipe[1]?$signed({2'd0,f1[7]}):b1_7;
if(valid_pipe[2])begin case(key2)
7'd0,7'd67:p3_7<=-($signed({{6{a2_7[9]}},a2_7}) <<< 2);
7'd4,7'd41:p3_7<=($signed({{6{a2_7[9]}},a2_7}) <<< 2);
7'd32:p3_7<=-($signed({{6{a2_7[9]}},a2_7}) <<< 1);
7'd33:p3_7<=($signed({{6{a2_7[9]}},a2_7}) <<< 4);
7'd36:p3_7<=-($signed({{6{a2_7[9]}},a2_7}) <<< 5);
7'd40:p3_7<=-($signed({{6{a2_7[9]}},a2_7}) <<< 6);
7'd64:p3_7<=-($signed({{6{a2_7[9]}},a2_7}) <<< 4);
7'd80,7'd82:p3_7<=($signed({{6{a2_7[9]}},a2_7}) <<< 1);
7'd66:p3_7<=($signed({{6{a2_7[9]}},a2_7}) <<< 3);
default:p3_7<=16'sd0;endcase end end end
logic signed [9:0] b1_8,a2_8;logic signed [15:0] p3_8;
always @(posedge clk)begin if(!rst_n)begin b1_8<=0;a2_8<=0;p3_8<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_8<=((-$signed({2'd0,x0[6]}) + $signed({2'd0,x0[8]})) + ($signed({2'd0,x0[12]}) + -$signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_8<=mode_pipe[1]?$signed({2'd0,f1[8]}):b1_8;
if(valid_pipe[2])begin case(key2)
7'd0,7'd33,7'd80:p3_8<=-($signed({{6{a2_8[9]}},a2_8}) <<< 1);
7'd4,7'd32:p3_8<=-($signed({{6{a2_8[9]}},a2_8}) <<< 5);
7'd36:p3_8<=($signed({{6{a2_8[9]}},a2_8}) <<< 5);
7'd37:p3_8<=($signed({{6{a2_8[9]}},a2_8}) <<< 6);
7'd40,7'd64:p3_8<=($signed({{6{a2_8[9]}},a2_8}) <<< 4);
7'd65,7'd66,7'd67:p3_8<=-($signed({{6{a2_8[9]}},a2_8}) <<< 2);
7'd81,7'd83:p3_8<=-($signed({{6{a2_8[9]}},a2_8}) <<< 0);
default:p3_8<=16'sd0;endcase end end end
logic signed [9:0] b1_9,a2_9;logic signed [15:0] p3_9;
always @(posedge clk)begin if(!rst_n)begin b1_9<=0;a2_9<=0;p3_9<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_9<=((-$signed({2'd0,x0[7]}) + -$signed({2'd0,x0[8]})) + ($signed({2'd0,x0[13]}) + $signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_9<=mode_pipe[1]?$signed({2'd0,f1[9]}):b1_9;
if(valid_pipe[2])begin case(key2)
7'd0:p3_9<=($signed({{6{a2_9[9]}},a2_9}) <<< 0);
7'd4:p3_9<=-($signed({{6{a2_9[9]}},a2_9}) <<< 3);
7'd32,7'd64:p3_9<=($signed({{6{a2_9[9]}},a2_9}) <<< 3);
7'd33,7'd40,7'd66:p3_9<=-($signed({{6{a2_9[9]}},a2_9}) <<< 4);
7'd36:p3_9<=($signed({{6{a2_9[9]}},a2_9}) <<< 5);
7'd37:p3_9<=($signed({{6{a2_9[9]}},a2_9}) <<< 6);
7'd41,7'd82,7'd83:p3_9<=-($signed({{6{a2_9[9]}},a2_9}) <<< 1);
7'd65,7'd67:p3_9<=($signed({{6{a2_9[9]}},a2_9}) <<< 4);
7'd81:p3_9<=-($signed({{6{a2_9[9]}},a2_9}) <<< 0);
default:p3_9<=16'sd0;endcase end end end
logic signed [9:0] b1_10,a2_10;logic signed [15:0] p3_10;
always @(posedge clk)begin if(!rst_n)begin b1_10<=0;a2_10<=0;p3_10<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_10<=(($signed({2'd0,x0[7]}) + -$signed({2'd0,x0[8]})) + (-$signed({2'd0,x0[13]}) + $signed({2'd0,x0[14]})));
if(valid_pipe[1])a2_10<=mode_pipe[1]?$signed({2'd0,f1[10]}):b1_10;
if(valid_pipe[2])begin case(key2)
7'd0,7'd37:p3_10<=($signed({{6{a2_10[9]}},a2_10}) <<< 5);
7'd4:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 6);
7'd32,7'd41:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 5);
7'd33,7'd64,7'd66:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 2);
7'd36:p3_10<=($signed({{6{a2_10[9]}},a2_10}) <<< 1);
7'd40:p3_10<=($signed({{6{a2_10[9]}},a2_10}) <<< 4);
7'd80:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 0);
7'd65,7'd83:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 1);
7'd67:p3_10<=-($signed({{6{a2_10[9]}},a2_10}) <<< 4);
default:p3_10<=16'sd0;endcase end end end
logic signed [9:0] b1_11,a2_11;logic signed [14:0] p3_11;
always @(posedge clk)begin if(!rst_n)begin b1_11<=0;a2_11<=0;p3_11<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_11<=((-$signed({2'd0,x0[7]}) + $signed({2'd0,x0[9]})) + ($signed({2'd0,x0[13]}) + -$signed({2'd0,x0[15]})));
if(valid_pipe[1])a2_11<=mode_pipe[1]?$signed({2'd0,f1[11]}):b1_11;
if(valid_pipe[2])begin case(key2)
7'd0,7'd37:p3_11<=($signed({{5{a2_11[9]}},a2_11}) <<< 5);
7'd4,7'd41:p3_11<=-($signed({{5{a2_11[9]}},a2_11}) <<< 5);
7'd32:p3_11<=-($signed({{5{a2_11[9]}},a2_11}) <<< 1);
7'd33:p3_11<=-($signed({{5{a2_11[9]}},a2_11}) <<< 4);
7'd36,7'd65:p3_11<=($signed({{5{a2_11[9]}},a2_11}) <<< 3);
7'd40,7'd64,7'd67:p3_11<=-($signed({{5{a2_11[9]}},a2_11}) <<< 3);
7'd80:p3_11<=-($signed({{5{a2_11[9]}},a2_11}) <<< 2);
7'd83:p3_11<=($signed({{5{a2_11[9]}},a2_11}) <<< 0);
default:p3_11<=15'sd0;endcase end end end
logic signed [9:0] b1_12,a2_12;logic signed [15:0] p3_12;
always @(posedge clk)begin if(!rst_n)begin b1_12<=0;a2_12<=0;p3_12<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_12<=(($signed({2'd0,x0[6]}) + -$signed({2'd0,x0[8]})) + (-$signed({2'd0,x0[18]}) + $signed({2'd0,x0[20]})));
if(valid_pipe[1])a2_12<=mode_pipe[1]?$signed({2'd0,f1[12]}):b1_12;
if(valid_pipe[2])begin case(key2)
7'd0,7'd37:p3_12<=($signed({{6{a2_12[9]}},a2_12}) <<< 5);
7'd32:p3_12<=-($signed({{6{a2_12[9]}},a2_12}) <<< 6);
7'd33,7'd36:p3_12<=($signed({{6{a2_12[9]}},a2_12}) <<< 6);
7'd64:p3_12<=-($signed({{6{a2_12[9]}},a2_12}) <<< 2);
7'd80:p3_12<=-($signed({{6{a2_12[9]}},a2_12}) <<< 0);
7'd65:p3_12<=($signed({{6{a2_12[9]}},a2_12}) <<< 3);
7'd67:p3_12<=-($signed({{6{a2_12[9]}},a2_12}) <<< 3);
7'd83:p3_12<=-($signed({{6{a2_12[9]}},a2_12}) <<< 1);
default:p3_12<=16'sd0;endcase end end end
logic signed [9:0] b1_13,a2_13;logic signed [14:0] p3_13;
always @(posedge clk)begin if(!rst_n)begin b1_13<=0;a2_13<=0;p3_13<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_13<=(($signed({2'd0,x0[7]}) + $signed({2'd0,x0[8]})) + (-$signed({2'd0,x0[19]}) + -$signed({2'd0,x0[20]})));
if(valid_pipe[1])a2_13<=mode_pipe[1]?$signed({2'd0,f1[13]}):b1_13;
if(valid_pipe[2])begin case(key2)
7'd0,7'd36,7'd37:p3_13<=($signed({{5{a2_13[9]}},a2_13}) <<< 3);
7'd4,7'd41,7'd67:p3_13<=($signed({{5{a2_13[9]}},a2_13}) <<< 4);
7'd32,7'd33:p3_13<=($signed({{5{a2_13[9]}},a2_13}) <<< 5);
7'd40:p3_13<=-($signed({{5{a2_13[9]}},a2_13}) <<< 5);
7'd64,7'd65,7'd66:p3_13<=-($signed({{5{a2_13[9]}},a2_13}) <<< 3);
7'd81:p3_13<=-($signed({{5{a2_13[9]}},a2_13}) <<< 1);
7'd82:p3_13<=-($signed({{5{a2_13[9]}},a2_13}) <<< 0);
7'd83:p3_13<=($signed({{5{a2_13[9]}},a2_13}) <<< 1);
default:p3_13<=15'sd0;endcase end end end
logic signed [9:0] b1_14,a2_14;logic signed [15:0] p3_14;
always @(posedge clk)begin if(!rst_n)begin b1_14<=0;a2_14<=0;p3_14<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_14<=((-$signed({2'd0,x0[7]}) + $signed({2'd0,x0[8]})) + ($signed({2'd0,x0[19]}) + -$signed({2'd0,x0[20]})));
if(valid_pipe[1])a2_14<=mode_pipe[1]?$signed({2'd0,f1[14]}):b1_14;
if(valid_pipe[2])begin case(key2)
7'd0:p3_14<=($signed({{6{a2_14[9]}},a2_14}) <<< 5);
7'd4:p3_14<=-($signed({{6{a2_14[9]}},a2_14}) <<< 4);
7'd32,7'd36,7'd40:p3_14<=-($signed({{6{a2_14[9]}},a2_14}) <<< 5);
7'd33,7'd64:p3_14<=($signed({{6{a2_14[9]}},a2_14}) <<< 3);
7'd37:p3_14<=($signed({{6{a2_14[9]}},a2_14}) <<< 6);
7'd41:p3_14<=-($signed({{6{a2_14[9]}},a2_14}) <<< 6);
7'd65:p3_14<=($signed({{6{a2_14[9]}},a2_14}) <<< 4);
7'd81,7'd82:p3_14<=-($signed({{6{a2_14[9]}},a2_14}) <<< 0);
7'd66:p3_14<=-($signed({{6{a2_14[9]}},a2_14}) <<< 2);
7'd67:p3_14<=($signed({{6{a2_14[9]}},a2_14}) <<< 2);
default:p3_14<=16'sd0;endcase end end end
logic signed [9:0] b1_15,a2_15;logic signed [15:0] p3_15;
always @(posedge clk)begin if(!rst_n)begin b1_15<=0;a2_15<=0;p3_15<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_15<=(($signed({2'd0,x0[7]}) + -$signed({2'd0,x0[9]})) + (-$signed({2'd0,x0[19]}) + $signed({2'd0,x0[21]})));
if(valid_pipe[1])a2_15<=mode_pipe[1]?$signed({2'd0,f1[15]}):b1_15;
if(valid_pipe[2])begin case(key2)
7'd0:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 4);
7'd32:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 5);
7'd36,7'd40:p3_15<=-($signed({{6{a2_15[9]}},a2_15}) <<< 6);
7'd37:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 6);
7'd41:p3_15<=-($signed({{6{a2_15[9]}},a2_15}) <<< 5);
7'd65,7'd67:p3_15<=-($signed({{6{a2_15[9]}},a2_15}) <<< 3);
7'd81,7'd83:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 0);
7'd66:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 2);
7'd82:p3_15<=($signed({{6{a2_15[9]}},a2_15}) <<< 1);
default:p3_15<=16'sd0;endcase end end end
logic signed [9:0] b1_16,a2_16;logic signed [14:0] p3_16;
always @(posedge clk)begin if(!rst_n)begin b1_16<=0;a2_16<=0;p3_16<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_16<=(($signed({2'd0,x0[3]}) + -$signed({2'd0,x0[4]})) + (-$signed({2'd0,x0[15]}) + $signed({2'd0,x0[16]})));
if(valid_pipe[1])a2_16<=mode_pipe[1]?$signed({2'd0,f1[16]}):b1_16;
if(valid_pipe[2])begin case(key2)
7'd0:p3_16<=-($signed({{5{a2_16[9]}},a2_16}) <<< 4);
7'd4,7'd37,7'd67:p3_16<=-($signed({{5{a2_16[9]}},a2_16}) <<< 3);
7'd33,7'd40,7'd66,7'd83:p3_16<=-($signed({{5{a2_16[9]}},a2_16}) <<< 2);
7'd36,7'd64:p3_16<=($signed({{5{a2_16[9]}},a2_16}) <<< 3);
7'd41:p3_16<=($signed({{5{a2_16[9]}},a2_16}) <<< 5);
7'd80:p3_16<=($signed({{5{a2_16[9]}},a2_16}) <<< 1);
default:p3_16<=15'sd0;endcase end end end
logic signed [8:0] b1_17,a2_17;logic signed [14:0] p3_17;
always @(posedge clk)begin if(!rst_n)begin b1_17<=0;a2_17<=0;p3_17<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_17<=($signed({1'd0,x0[4]}) + -$signed({1'd0,x0[16]}));
if(valid_pipe[1])a2_17<=mode_pipe[1]?$signed({1'd0,f1[17]}):b1_17;
if(valid_pipe[2])begin case(key2)
7'd0:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 6);
7'd4,7'd32:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 5);
7'd33,7'd66:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 4);
7'd36,7'd41,7'd65:p3_17<=($signed({{6{a2_17[8]}},a2_17}) <<< 4);
7'd37,7'd40,7'd82:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 1);
7'd64:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 3);
7'd80,7'd81:p3_17<=-($signed({{6{a2_17[8]}},a2_17}) <<< 0);
default:p3_17<=15'sd0;endcase end end end
logic signed [9:0] b1_18,a2_18;logic signed [14:0] p3_18;
always @(posedge clk)begin if(!rst_n)begin b1_18<=0;a2_18<=0;p3_18<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_18<=((-$signed({2'd0,x0[4]}) + $signed({2'd0,x0[5]})) + ($signed({2'd0,x0[16]}) + -$signed({2'd0,x0[17]})));
if(valid_pipe[1])a2_18<=mode_pipe[1]?$signed({2'd0,f1[18]}):b1_18;
if(valid_pipe[2])begin case(key2)
7'd0,7'd32:p3_18<=-($signed({{5{a2_18[9]}},a2_18}) <<< 5);
7'd4,7'd33,7'd64,7'd66:p3_18<=-($signed({{5{a2_18[9]}},a2_18}) <<< 4);
7'd36,7'd37,7'd67:p3_18<=($signed({{5{a2_18[9]}},a2_18}) <<< 3);
7'd40:p3_18<=($signed({{5{a2_18[9]}},a2_18}) <<< 2);
7'd41:p3_18<=-($signed({{5{a2_18[9]}},a2_18}) <<< 3);
7'd80:p3_18<=-($signed({{5{a2_18[9]}},a2_18}) <<< 0);
7'd65:p3_18<=-($signed({{5{a2_18[9]}},a2_18}) <<< 1);
7'd82,7'd83:p3_18<=($signed({{5{a2_18[9]}},a2_18}) <<< 1);
default:p3_18<=15'sd0;endcase end end end
logic signed [9:0] b1_19,a2_19;logic signed [14:0] p3_19;
always @(posedge clk)begin if(!rst_n)begin b1_19<=0;a2_19<=0;p3_19<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_19<=(($signed({2'd0,x0[9]}) + -$signed({2'd0,x0[10]})) + ($signed({2'd0,x0[15]}) + -$signed({2'd0,x0[16]})));
if(valid_pipe[1])a2_19<=mode_pipe[1]?$signed({2'd0,f1[19]}):b1_19;
if(valid_pipe[2])begin case(key2)
7'd0,7'd40,7'd80,7'd66:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 2);
7'd4,7'd37,7'd64:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 3);
7'd32:p3_19<=($signed({{5{a2_19[9]}},a2_19}) <<< 1);
7'd33:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 5);
7'd36,7'd41:p3_19<=($signed({{5{a2_19[9]}},a2_19}) <<< 3);
7'd65,7'd67:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 4);
7'd82:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 1);
7'd83:p3_19<=-($signed({{5{a2_19[9]}},a2_19}) <<< 0);
default:p3_19<=15'sd0;endcase end end end
logic signed [9:0] b1_20,a2_20;logic signed [14:0] p3_20;
always @(posedge clk)begin if(!rst_n)begin b1_20<=0;a2_20<=0;p3_20<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_20<=($signed({2'd0,x0[10]}) + $signed({2'd0,x0[16]}));
if(valid_pipe[1])a2_20<=mode_pipe[1]?$signed({2'd0,f1[20]}):b1_20;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4,7'd33:p3_20<=-($signed({{5{a2_20[9]}},a2_20}) <<< 5);
7'd32,7'd64:p3_20<=-($signed({{5{a2_20[9]}},a2_20}) <<< 4);
7'd36:p3_20<=($signed({{5{a2_20[9]}},a2_20}) <<< 5);
7'd37,7'd40,7'd41:p3_20<=-($signed({{5{a2_20[9]}},a2_20}) <<< 3);
7'd65,7'd66,7'd83:p3_20<=($signed({{5{a2_20[9]}},a2_20}) <<< 2);
7'd81,7'd82:p3_20<=($signed({{5{a2_20[9]}},a2_20}) <<< 0);
7'd67:p3_20<=($signed({{5{a2_20[9]}},a2_20}) <<< 3);
default:p3_20<=15'sd0;endcase end end end
logic signed [9:0] b1_21,a2_21;logic signed [14:0] p3_21;
always @(posedge clk)begin if(!rst_n)begin b1_21<=0;a2_21<=0;p3_21<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_21<=((-$signed({2'd0,x0[10]}) + $signed({2'd0,x0[11]})) + (-$signed({2'd0,x0[16]}) + $signed({2'd0,x0[17]})));
if(valid_pipe[1])a2_21<=mode_pipe[1]?$signed({2'd0,f1[21]}):b1_21;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4:p3_21<=-($signed({{5{a2_21[9]}},a2_21}) <<< 5);
7'd32,7'd41:p3_21<=-($signed({{5{a2_21[9]}},a2_21}) <<< 4);
7'd36:p3_21<=($signed({{5{a2_21[9]}},a2_21}) <<< 4);
7'd37,7'd82:p3_21<=($signed({{5{a2_21[9]}},a2_21}) <<< 0);
7'd40:p3_21<=-($signed({{5{a2_21[9]}},a2_21}) <<< 1);
7'd64:p3_21<=($signed({{5{a2_21[9]}},a2_21}) <<< 1);
7'd66:p3_21<=-($signed({{5{a2_21[9]}},a2_21}) <<< 3);
7'd67:p3_21<=($signed({{5{a2_21[9]}},a2_21}) <<< 3);
7'd83:p3_21<=($signed({{5{a2_21[9]}},a2_21}) <<< 2);
default:p3_21<=15'sd0;endcase end end end
logic signed [9:0] b1_22,a2_22;logic signed [14:0] p3_22;
always @(posedge clk)begin if(!rst_n)begin b1_22<=0;a2_22<=0;p3_22<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_22<=((-$signed({2'd0,x0[9]}) + $signed({2'd0,x0[10]})) + ($signed({2'd0,x0[15]}) + -$signed({2'd0,x0[16]})));
if(valid_pipe[1])a2_22<=mode_pipe[1]?$signed({2'd0,f1[22]}):b1_22;
if(valid_pipe[2])begin case(key2)
7'd0,7'd32,7'd36:p3_22<=-($signed({{5{a2_22[9]}},a2_22}) <<< 4);
7'd4,7'd37:p3_22<=-($signed({{5{a2_22[9]}},a2_22}) <<< 3);
7'd33:p3_22<=-($signed({{5{a2_22[9]}},a2_22}) <<< 2);
7'd40:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 2);
7'd41:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 5);
7'd65,7'd66:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 4);
7'd81:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 0);
7'd82:p3_22<=-($signed({{5{a2_22[9]}},a2_22}) <<< 0);
7'd67:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 3);
7'd83:p3_22<=($signed({{5{a2_22[9]}},a2_22}) <<< 1);
default:p3_22<=15'sd0;endcase end end end
logic signed [8:0] b1_23,a2_23;logic signed [14:0] p3_23;
always @(posedge clk)begin if(!rst_n)begin b1_23<=0;a2_23<=0;p3_23<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_23<=(-$signed({1'd0,x0[10]}) + $signed({1'd0,x0[16]}));
if(valid_pipe[1])a2_23<=mode_pipe[1]?$signed({1'd0,f1[23]}):b1_23;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 4);
7'd32:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 6);
7'd33,7'd36:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 5);
7'd37,7'd40:p3_23<=($signed({{6{a2_23[8]}},a2_23}) <<< 3);
7'd41:p3_23<=($signed({{6{a2_23[8]}},a2_23}) <<< 5);
7'd64,7'd65,7'd67:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 3);
7'd80:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 2);
7'd81:p3_23<=($signed({{6{a2_23[8]}},a2_23}) <<< 0);
7'd66:p3_23<=($signed({{6{a2_23[8]}},a2_23}) <<< 4);
7'd82:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 1);
7'd83:p3_23<=-($signed({{6{a2_23[8]}},a2_23}) <<< 0);
default:p3_23<=15'sd0;endcase end end end
logic signed [9:0] b1_24,a2_24;logic signed [14:0] p3_24;
always @(posedge clk)begin if(!rst_n)begin b1_24<=0;a2_24<=0;p3_24<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_24<=(($signed({2'd0,x0[10]}) + -$signed({2'd0,x0[11]})) + (-$signed({2'd0,x0[16]}) + $signed({2'd0,x0[17]})));
if(valid_pipe[1])a2_24<=mode_pipe[1]?$signed({2'd0,f1[24]}):b1_24;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4,7'd65:p3_24<=-($signed({{5{a2_24[9]}},a2_24}) <<< 2);
7'd32,7'd33:p3_24<=-($signed({{5{a2_24[9]}},a2_24}) <<< 5);
7'd36:p3_24<=-($signed({{5{a2_24[9]}},a2_24}) <<< 3);
7'd37:p3_24<=($signed({{5{a2_24[9]}},a2_24}) <<< 4);
7'd40,7'd64,7'd66,7'd67:p3_24<=($signed({{5{a2_24[9]}},a2_24}) <<< 3);
7'd41:p3_24<=-($signed({{5{a2_24[9]}},a2_24}) <<< 1);
7'd80,7'd83:p3_24<=($signed({{5{a2_24[9]}},a2_24}) <<< 2);
7'd81:p3_24<=-($signed({{5{a2_24[9]}},a2_24}) <<< 0);
default:p3_24<=15'sd0;endcase end end end
logic signed [9:0] b1_25,a2_25;logic signed [14:0] p3_25;
always @(posedge clk)begin if(!rst_n)begin b1_25<=0;a2_25<=0;p3_25<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_25<=(($signed({2'd0,x0[9]}) + -$signed({2'd0,x0[10]})) + (-$signed({2'd0,x0[21]}) + $signed({2'd0,x0[22]})));
if(valid_pipe[1])a2_25<=mode_pipe[1]?$signed({2'd0,f1[25]}):b1_25;
if(valid_pipe[2])begin case(key2)
7'd0,7'd40:p3_25<=($signed({{5{a2_25[9]}},a2_25}) <<< 2);
7'd4:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 2);
7'd32,7'd37,7'd64:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 3);
7'd33:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 5);
7'd36,7'd66:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 4);
7'd41:p3_25<=($signed({{5{a2_25[9]}},a2_25}) <<< 4);
7'd80:p3_25<=($signed({{5{a2_25[9]}},a2_25}) <<< 0);
7'd65:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 1);
7'd81,7'd83:p3_25<=-($signed({{5{a2_25[9]}},a2_25}) <<< 0);
7'd67:p3_25<=($signed({{5{a2_25[9]}},a2_25}) <<< 3);
default:p3_25<=15'sd0;endcase end end end
logic signed [8:0] b1_26,a2_26;logic signed [14:0] p3_26;
always @(posedge clk)begin if(!rst_n)begin b1_26<=0;a2_26<=0;p3_26<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_26<=($signed({1'd0,x0[10]}) + -$signed({1'd0,x0[22]}));
if(valid_pipe[1])a2_26<=mode_pipe[1]?$signed({1'd0,f1[26]}):b1_26;
if(valid_pipe[2])begin case(key2)
7'd4,7'd36:p3_26<=-($signed({{6{a2_26[8]}},a2_26}) <<< 3);
7'd32:p3_26<=-($signed({{6{a2_26[8]}},a2_26}) <<< 5);
7'd33:p3_26<=-($signed({{6{a2_26[8]}},a2_26}) <<< 6);
7'd37,7'd64:p3_26<=($signed({{6{a2_26[8]}},a2_26}) <<< 1);
7'd40:p3_26<=($signed({{6{a2_26[8]}},a2_26}) <<< 2);
7'd41,7'd66,7'd67:p3_26<=($signed({{6{a2_26[8]}},a2_26}) <<< 3);
7'd82:p3_26<=($signed({{6{a2_26[8]}},a2_26}) <<< 0);
default:p3_26<=15'sd0;endcase end end end
logic signed [9:0] b1_27,a2_27;logic signed [13:0] p3_27;
always @(posedge clk)begin if(!rst_n)begin b1_27<=0;a2_27<=0;p3_27<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_27<=((-$signed({2'd0,x0[10]}) + $signed({2'd0,x0[11]})) + ($signed({2'd0,x0[22]}) + -$signed({2'd0,x0[23]})));
if(valid_pipe[1])a2_27<=mode_pipe[1]?$signed({2'd0,f1[27]}):b1_27;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4:p3_27<=-($signed({{4{a2_27[9]}},a2_27}) <<< 2);
7'd32,7'd33:p3_27<=-($signed({{4{a2_27[9]}},a2_27}) <<< 4);
7'd36,7'd82:p3_27<=($signed({{4{a2_27[9]}},a2_27}) <<< 2);
7'd37,7'd66,7'd67:p3_27<=($signed({{4{a2_27[9]}},a2_27}) <<< 3);
7'd41:p3_27<=-($signed({{4{a2_27[9]}},a2_27}) <<< 3);
7'd64:p3_27<=($signed({{4{a2_27[9]}},a2_27}) <<< 1);
7'd80:p3_27<=($signed({{4{a2_27[9]}},a2_27}) <<< 0);
7'd65:p3_27<=-($signed({{4{a2_27[9]}},a2_27}) <<< 1);
7'd81:p3_27<=-($signed({{4{a2_27[9]}},a2_27}) <<< 0);
default:p3_27<=14'sd0;endcase end end end
logic signed [9:0] b1_28,a2_28;logic signed [14:0] p3_28;
always @(posedge clk)begin if(!rst_n)begin b1_28<=0;a2_28<=0;p3_28<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_28<=(($signed({2'd0,x0[18]}) + -$signed({2'd0,x0[20]})) + (-$signed({2'd0,x0[24]}) + $signed({2'd0,x0[26]})));
if(valid_pipe[1])a2_28<=mode_pipe[1]?$signed({2'd0,f1[28]}):b1_28;
if(valid_pipe[2])begin case(key2)
7'd0:p3_28<=-($signed({{5{a2_28[9]}},a2_28}) <<< 3);
7'd4,7'd37,7'd40,7'd66:p3_28<=($signed({{5{a2_28[9]}},a2_28}) <<< 4);
7'd33:p3_28<=($signed({{5{a2_28[9]}},a2_28}) <<< 5);
7'd36:p3_28<=-($signed({{5{a2_28[9]}},a2_28}) <<< 5);
7'd64:p3_28<=-($signed({{5{a2_28[9]}},a2_28}) <<< 2);
7'd80,7'd82:p3_28<=-($signed({{5{a2_28[9]}},a2_28}) <<< 0);
7'd65,7'd83:p3_28<=($signed({{5{a2_28[9]}},a2_28}) <<< 2);
7'd67:p3_28<=($signed({{5{a2_28[9]}},a2_28}) <<< 3);
default:p3_28<=15'sd0;endcase end end end
logic signed [9:0] b1_29,a2_29;logic signed [13:0] p3_29;
always @(posedge clk)begin if(!rst_n)begin b1_29<=0;a2_29<=0;p3_29<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_29<=(($signed({2'd0,x0[19]}) + $signed({2'd0,x0[20]})) + (-$signed({2'd0,x0[25]}) + -$signed({2'd0,x0[26]})));
if(valid_pipe[1])a2_29<=mode_pipe[1]?$signed({2'd0,f1[29]}):b1_29;
if(valid_pipe[2])begin case(key2)
7'd0,7'd33,7'd41:p3_29<=($signed({{4{a2_29[9]}},a2_29}) <<< 3);
7'd32:p3_29<=-($signed({{4{a2_29[9]}},a2_29}) <<< 4);
7'd36,7'd37,7'd65:p3_29<=-($signed({{4{a2_29[9]}},a2_29}) <<< 3);
7'd40,7'd64:p3_29<=($signed({{4{a2_29[9]}},a2_29}) <<< 4);
7'd80:p3_29<=-($signed({{4{a2_29[9]}},a2_29}) <<< 1);
7'd66:p3_29<=($signed({{4{a2_29[9]}},a2_29}) <<< 1);
default:p3_29<=14'sd0;endcase end end end
logic signed [9:0] b1_30,a2_30;logic signed [14:0] p3_30;
always @(posedge clk)begin if(!rst_n)begin b1_30<=0;a2_30<=0;p3_30<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_30<=((-$signed({2'd0,x0[19]}) + $signed({2'd0,x0[20]})) + ($signed({2'd0,x0[25]}) + -$signed({2'd0,x0[26]})));
if(valid_pipe[1])a2_30<=mode_pipe[1]?$signed({2'd0,f1[30]}):b1_30;
if(valid_pipe[2])begin case(key2)
7'd0,7'd67:p3_30<=-($signed({{5{a2_30[9]}},a2_30}) <<< 3);
7'd4,7'd64:p3_30<=-($signed({{5{a2_30[9]}},a2_30}) <<< 2);
7'd32,7'd65:p3_30<=-($signed({{5{a2_30[9]}},a2_30}) <<< 4);
7'd33,7'd40:p3_30<=($signed({{5{a2_30[9]}},a2_30}) <<< 5);
7'd36,7'd66:p3_30<=($signed({{5{a2_30[9]}},a2_30}) <<< 3);
7'd37,7'd41:p3_30<=($signed({{5{a2_30[9]}},a2_30}) <<< 4);
7'd80:p3_30<=-($signed({{5{a2_30[9]}},a2_30}) <<< 1);
7'd81,7'd82:p3_30<=($signed({{5{a2_30[9]}},a2_30}) <<< 1);
7'd83:p3_30<=($signed({{5{a2_30[9]}},a2_30}) <<< 0);
default:p3_30<=15'sd0;endcase end end end
logic signed [9:0] b1_31,a2_31;logic signed [14:0] p3_31;
always @(posedge clk)begin if(!rst_n)begin b1_31<=0;a2_31<=0;p3_31<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_31<=(($signed({2'd0,x0[19]}) + -$signed({2'd0,x0[21]})) + (-$signed({2'd0,x0[25]}) + $signed({2'd0,x0[27]})));
if(valid_pipe[1])a2_31<=mode_pipe[1]?$signed({2'd0,f1[31]}):b1_31;
if(valid_pipe[2])begin case(key2)
7'd0,7'd64,7'd65:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 3);
7'd4:p3_31<=-($signed({{5{a2_31[9]}},a2_31}) <<< 4);
7'd32:p3_31<=-($signed({{5{a2_31[9]}},a2_31}) <<< 5);
7'd33,7'd41:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 4);
7'd36,7'd40:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 5);
7'd37:p3_31<=-($signed({{5{a2_31[9]}},a2_31}) <<< 2);
7'd80:p3_31<=-($signed({{5{a2_31[9]}},a2_31}) <<< 0);
7'd81:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 2);
7'd66:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 1);
7'd82:p3_31<=($signed({{5{a2_31[9]}},a2_31}) <<< 0);
default:p3_31<=15'sd0;endcase end end end
logic signed [8:0] b1_32,a2_32;logic signed [13:0] p3_32;
always @(posedge clk)begin if(!rst_n)begin b1_32<=0;a2_32<=0;p3_32<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_32<=($signed({1'd0,x0[24]}) + -$signed({1'd0,x0[26]}));
if(valid_pipe[1])a2_32<=mode_pipe[1]?$signed({1'd0,f1[32]}):b1_32;
if(valid_pipe[2])begin case(key2)
7'd0,7'd64:p3_32<=-($signed({{5{a2_32[8]}},a2_32}) <<< 3);
7'd4,7'd83:p3_32<=-($signed({{5{a2_32[8]}},a2_32}) <<< 1);
7'd32,7'd36,7'd41:p3_32<=-($signed({{5{a2_32[8]}},a2_32}) <<< 5);
7'd33:p3_32<=($signed({{5{a2_32[8]}},a2_32}) <<< 5);
7'd37:p3_32<=($signed({{5{a2_32[8]}},a2_32}) <<< 3);
7'd40,7'd65,7'd66:p3_32<=-($signed({{5{a2_32[8]}},a2_32}) <<< 4);
7'd80:p3_32<=-($signed({{5{a2_32[8]}},a2_32}) <<< 2);
7'd81:p3_32<=($signed({{5{a2_32[8]}},a2_32}) <<< 0);
7'd67:p3_32<=($signed({{5{a2_32[8]}},a2_32}) <<< 4);
default:p3_32<=14'sd0;endcase end end end
logic signed [9:0] b1_33,a2_33;logic signed [15:0] p3_33;
always @(posedge clk)begin if(!rst_n)begin b1_33<=0;a2_33<=0;p3_33<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_33<=($signed({2'd0,x0[25]}) + $signed({2'd0,x0[26]}));
if(valid_pipe[1])a2_33<=mode_pipe[1]?$signed({2'd0,f1[33]}):b1_33;
if(valid_pipe[2])begin case(key2)
7'd0,7'd36,7'd64:p3_33<=($signed({{6{a2_33[9]}},a2_33}) <<< 4);
7'd4,7'd80,7'd66,7'd67:p3_33<=($signed({{6{a2_33[9]}},a2_33}) <<< 1);
7'd32:p3_33<=-($signed({{6{a2_33[9]}},a2_33}) <<< 6);
7'd33,7'd41:p3_33<=($signed({{6{a2_33[9]}},a2_33}) <<< 5);
7'd37:p3_33<=-($signed({{6{a2_33[9]}},a2_33}) <<< 3);
7'd40:p3_33<=-($signed({{6{a2_33[9]}},a2_33}) <<< 4);
7'd65:p3_33<=-($signed({{6{a2_33[9]}},a2_33}) <<< 2);
7'd81:p3_33<=-($signed({{6{a2_33[9]}},a2_33}) <<< 0);
7'd82:p3_33<=($signed({{6{a2_33[9]}},a2_33}) <<< 0);
default:p3_33<=16'sd0;endcase end end end
logic signed [8:0] b1_34,a2_34;logic signed [13:0] p3_34;
always @(posedge clk)begin if(!rst_n)begin b1_34<=0;a2_34<=0;p3_34<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_34<=(-$signed({1'd0,x0[25]}) + $signed({1'd0,x0[26]}));
if(valid_pipe[1])a2_34<=mode_pipe[1]?$signed({1'd0,f1[34]}):b1_34;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4,7'd66:p3_34<=-($signed({{5{a2_34[8]}},a2_34}) <<< 3);
7'd32:p3_34<=-($signed({{5{a2_34[8]}},a2_34}) <<< 5);
7'd33,7'd40:p3_34<=($signed({{5{a2_34[8]}},a2_34}) <<< 5);
7'd36,7'd67:p3_34<=($signed({{5{a2_34[8]}},a2_34}) <<< 4);
7'd37:p3_34<=-($signed({{5{a2_34[8]}},a2_34}) <<< 2);
7'd41:p3_34<=-($signed({{5{a2_34[8]}},a2_34}) <<< 0);
7'd64,7'd81:p3_34<=($signed({{5{a2_34[8]}},a2_34}) <<< 2);
7'd80,7'd83:p3_34<=($signed({{5{a2_34[8]}},a2_34}) <<< 0);
7'd65:p3_34<=($signed({{5{a2_34[8]}},a2_34}) <<< 3);
7'd82:p3_34<=-($signed({{5{a2_34[8]}},a2_34}) <<< 1);
default:p3_34<=14'sd0;endcase end end end
logic signed [8:0] b1_35,a2_35;logic signed [14:0] p3_35;
always @(posedge clk)begin if(!rst_n)begin b1_35<=0;a2_35<=0;p3_35<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_35<=($signed({1'd0,x0[25]}) + -$signed({1'd0,x0[27]}));
if(valid_pipe[1])a2_35<=mode_pipe[1]?$signed({1'd0,f1[35]}):b1_35;
if(valid_pipe[2])begin case(key2)
7'd0,7'd66:p3_35<=($signed({{6{a2_35[8]}},a2_35}) <<< 4);
7'd4,7'd64,7'd81:p3_35<=-($signed({{6{a2_35[8]}},a2_35}) <<< 2);
7'd32:p3_35<=-($signed({{6{a2_35[8]}},a2_35}) <<< 6);
7'd33,7'd40:p3_35<=($signed({{6{a2_35[8]}},a2_35}) <<< 5);
7'd36,7'd41:p3_35<=($signed({{6{a2_35[8]}},a2_35}) <<< 6);
7'd37:p3_35<=-($signed({{6{a2_35[8]}},a2_35}) <<< 4);
7'd80:p3_35<=-($signed({{6{a2_35[8]}},a2_35}) <<< 0);
7'd65:p3_35<=-($signed({{6{a2_35[8]}},a2_35}) <<< 3);
7'd82:p3_35<=($signed({{6{a2_35[8]}},a2_35}) <<< 0);
default:p3_35<=15'sd0;endcase end end end
logic signed [9:0] b1_36,a2_36;logic signed [14:0] p3_36;
always @(posedge clk)begin if(!rst_n)begin b1_36<=0;a2_36<=0;p3_36<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_36<=((-$signed({2'd0,x0[24]}) + $signed({2'd0,x0[26]})) + ($signed({2'd0,x0[30]}) + -$signed({2'd0,x0[32]})));
if(valid_pipe[1])a2_36<=mode_pipe[1]?$signed({2'd0,f1[36]}):b1_36;
if(valid_pipe[2])begin case(key2)
7'd4:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 4);
7'd32,7'd40,7'd41:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 5);
7'd33:p3_36<=($signed({{5{a2_36[9]}},a2_36}) <<< 4);
7'd37,7'd65,7'd82,7'd67:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 2);
7'd64,7'd66:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 3);
7'd80,7'd83:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 1);
7'd81:p3_36<=-($signed({{5{a2_36[9]}},a2_36}) <<< 0);
default:p3_36<=15'sd0;endcase end end end
logic signed [9:0] b1_37,a2_37;logic signed [14:0] p3_37;
always @(posedge clk)begin if(!rst_n)begin b1_37<=0;a2_37<=0;p3_37<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_37<=((-$signed({2'd0,x0[25]}) + -$signed({2'd0,x0[26]})) + ($signed({2'd0,x0[31]}) + $signed({2'd0,x0[32]})));
if(valid_pipe[1])a2_37<=mode_pipe[1]?$signed({2'd0,f1[37]}):b1_37;
if(valid_pipe[2])begin case(key2)
7'd0:p3_37<=($signed({{5{a2_37[9]}},a2_37}) <<< 3);
7'd4:p3_37<=($signed({{5{a2_37[9]}},a2_37}) <<< 1);
7'd32,7'd40:p3_37<=-($signed({{5{a2_37[9]}},a2_37}) <<< 5);
7'd33,7'd41,7'd66:p3_37<=($signed({{5{a2_37[9]}},a2_37}) <<< 4);
7'd36:p3_37<=($signed({{5{a2_37[9]}},a2_37}) <<< 5);
7'd37,7'd80:p3_37<=($signed({{5{a2_37[9]}},a2_37}) <<< 0);
7'd64:p3_37<=-($signed({{5{a2_37[9]}},a2_37}) <<< 3);
7'd67:p3_37<=-($signed({{5{a2_37[9]}},a2_37}) <<< 1);
default:p3_37<=15'sd0;endcase end end end
logic signed [9:0] b1_38,a2_38;logic signed [14:0] p3_38;
always @(posedge clk)begin if(!rst_n)begin b1_38<=0;a2_38<=0;p3_38<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_38<=(($signed({2'd0,x0[25]}) + -$signed({2'd0,x0[26]})) + (-$signed({2'd0,x0[31]}) + $signed({2'd0,x0[32]})));
if(valid_pipe[1])a2_38<=mode_pipe[1]?$signed({2'd0,f1[38]}):b1_38;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 1);
7'd32:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 5);
7'd33,7'd67:p3_38<=($signed({{5{a2_38[9]}},a2_38}) <<< 2);
7'd36,7'd65:p3_38<=($signed({{5{a2_38[9]}},a2_38}) <<< 3);
7'd37,7'd41:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 4);
7'd64,7'd66:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 3);
7'd80:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 2);
7'd81:p3_38<=($signed({{5{a2_38[9]}},a2_38}) <<< 1);
7'd82:p3_38<=-($signed({{5{a2_38[9]}},a2_38}) <<< 0);
default:p3_38<=15'sd0;endcase end end end
logic signed [9:0] b1_39,a2_39;logic signed [14:0] p3_39;
always @(posedge clk)begin if(!rst_n)begin b1_39<=0;a2_39<=0;p3_39<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_39<=((-$signed({2'd0,x0[25]}) + $signed({2'd0,x0[27]})) + ($signed({2'd0,x0[31]}) + -$signed({2'd0,x0[33]})));
if(valid_pipe[1])a2_39<=mode_pipe[1]?$signed({2'd0,f1[39]}):b1_39;
if(valid_pipe[2])begin case(key2)
7'd0,7'd65,7'd66:p3_39<=($signed({{5{a2_39[9]}},a2_39}) <<< 3);
7'd4:p3_39<=($signed({{5{a2_39[9]}},a2_39}) <<< 4);
7'd32:p3_39<=-($signed({{5{a2_39[9]}},a2_39}) <<< 5);
7'd33:p3_39<=($signed({{5{a2_39[9]}},a2_39}) <<< 2);
7'd36,7'd41:p3_39<=($signed({{5{a2_39[9]}},a2_39}) <<< 5);
7'd37,7'd64:p3_39<=-($signed({{5{a2_39[9]}},a2_39}) <<< 4);
7'd81,7'd82:p3_39<=($signed({{5{a2_39[9]}},a2_39}) <<< 1);
7'd67:p3_39<=-($signed({{5{a2_39[9]}},a2_39}) <<< 3);
7'd83:p3_39<=-($signed({{5{a2_39[9]}},a2_39}) <<< 1);
default:p3_39<=15'sd0;endcase end end end
logic signed [9:0] b1_40,a2_40;logic signed [13:0] p3_40;
always @(posedge clk)begin if(!rst_n)begin b1_40<=0;a2_40<=0;p3_40<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_40<=(($signed({2'd0,x0[21]}) + -$signed({2'd0,x0[22]})) + (-$signed({2'd0,x0[27]}) + $signed({2'd0,x0[28]})));
if(valid_pipe[1])a2_40<=mode_pipe[1]?$signed({2'd0,f1[40]}):b1_40;
if(valid_pipe[2])begin case(key2)
7'd4,7'd36,7'd82:p3_40<=-($signed({{4{a2_40[9]}},a2_40}) <<< 1);
7'd32,7'd66:p3_40<=($signed({{4{a2_40[9]}},a2_40}) <<< 4);
7'd33,7'd67:p3_40<=-($signed({{4{a2_40[9]}},a2_40}) <<< 3);
7'd40,7'd81:p3_40<=($signed({{4{a2_40[9]}},a2_40}) <<< 1);
7'd41,7'd65:p3_40<=($signed({{4{a2_40[9]}},a2_40}) <<< 3);
7'd64:p3_40<=-($signed({{4{a2_40[9]}},a2_40}) <<< 2);
7'd83:p3_40<=($signed({{4{a2_40[9]}},a2_40}) <<< 0);
default:p3_40<=14'sd0;endcase end end end
logic signed [8:0] b1_41,a2_41;logic signed [13:0] p3_41;
always @(posedge clk)begin if(!rst_n)begin b1_41<=0;a2_41<=0;p3_41<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_41<=($signed({1'd0,x0[22]}) + -$signed({1'd0,x0[28]}));
if(valid_pipe[1])a2_41<=mode_pipe[1]?$signed({1'd0,f1[41]}):b1_41;
if(valid_pipe[2])begin case(key2)
7'd0,7'd64,7'd65,7'd66,7'd67:p3_41<=($signed({{5{a2_41[8]}},a2_41}) <<< 3);
7'd4,7'd36,7'd37:p3_41<=-($signed({{5{a2_41[8]}},a2_41}) <<< 3);
7'd32,7'd40,7'd41:p3_41<=($signed({{5{a2_41[8]}},a2_41}) <<< 4);
7'd33:p3_41<=-($signed({{5{a2_41[8]}},a2_41}) <<< 5);
7'd81,7'd82:p3_41<=($signed({{5{a2_41[8]}},a2_41}) <<< 1);
7'd83:p3_41<=($signed({{5{a2_41[8]}},a2_41}) <<< 0);
default:p3_41<=14'sd0;endcase end end end
logic signed [9:0] b1_42,a2_42;logic signed [13:0] p3_42;
always @(posedge clk)begin if(!rst_n)begin b1_42<=0;a2_42<=0;p3_42<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_42<=((-$signed({2'd0,x0[22]}) + $signed({2'd0,x0[23]})) + ($signed({2'd0,x0[28]}) + -$signed({2'd0,x0[29]})));
if(valid_pipe[1])a2_42<=mode_pipe[1]?$signed({2'd0,f1[42]}):b1_42;
if(valid_pipe[2])begin case(key2)
7'd0,7'd40,7'd41:p3_42<=($signed({{4{a2_42[9]}},a2_42}) <<< 3);
7'd4,7'd36:p3_42<=-($signed({{4{a2_42[9]}},a2_42}) <<< 2);
7'd33:p3_42<=-($signed({{4{a2_42[9]}},a2_42}) <<< 4);
7'd37,7'd67:p3_42<=-($signed({{4{a2_42[9]}},a2_42}) <<< 3);
7'd64,7'd65:p3_42<=($signed({{4{a2_42[9]}},a2_42}) <<< 4);
7'd80:p3_42<=($signed({{4{a2_42[9]}},a2_42}) <<< 1);
7'd81:p3_42<=-($signed({{4{a2_42[9]}},a2_42}) <<< 0);
7'd83:p3_42<=($signed({{4{a2_42[9]}},a2_42}) <<< 0);
default:p3_42<=14'sd0;endcase end end end
logic signed [8:0] b1_43,a2_43;logic signed [12:0] p3_43;
always @(posedge clk)begin if(!rst_n)begin b1_43<=0;a2_43<=0;p3_43<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_43<=($signed({1'd0,x0[27]}) + -$signed({1'd0,x0[28]}));
if(valid_pipe[1])a2_43<=mode_pipe[1]?$signed({1'd0,f1[43]}):b1_43;
if(valid_pipe[2])begin case(key2)
7'd4,7'd33:p3_43<=-($signed({{4{a2_43[8]}},a2_43}) <<< 2);
7'd32,7'd41,7'd65:p3_43<=($signed({{4{a2_43[8]}},a2_43}) <<< 4);
7'd36,7'd83:p3_43<=($signed({{4{a2_43[8]}},a2_43}) <<< 1);
7'd40:p3_43<=($signed({{4{a2_43[8]}},a2_43}) <<< 2);
7'd64:p3_43<=-($signed({{4{a2_43[8]}},a2_43}) <<< 4);
7'd80,7'd82:p3_43<=-($signed({{4{a2_43[8]}},a2_43}) <<< 1);
7'd66:p3_43<=-($signed({{4{a2_43[8]}},a2_43}) <<< 3);
7'd67:p3_43<=($signed({{4{a2_43[8]}},a2_43}) <<< 3);
default:p3_43<=13'sd0;endcase end end end
logic signed [8:0] b1_44,a2_44;logic signed [13:0] p3_44;
always @(posedge clk)begin if(!rst_n)begin b1_44<=0;a2_44<=0;p3_44<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_44<=$signed({1'd0,x0[28]});
if(valid_pipe[1])a2_44<=mode_pipe[1]?$signed({1'd0,f1[44]}):b1_44;
if(valid_pipe[2])begin case(key2)
7'd0,7'd32,7'd41:p3_44<=($signed({{5{a2_44[8]}},a2_44}) <<< 4);
7'd4:p3_44<=-($signed({{5{a2_44[8]}},a2_44}) <<< 1);
7'd33:p3_44<=-($signed({{5{a2_44[8]}},a2_44}) <<< 5);
7'd36:p3_44<=-($signed({{5{a2_44[8]}},a2_44}) <<< 2);
7'd37,7'd64:p3_44<=($signed({{5{a2_44[8]}},a2_44}) <<< 2);
7'd40,7'd66:p3_44<=($signed({{5{a2_44[8]}},a2_44}) <<< 3);
7'd80,7'd82:p3_44<=($signed({{5{a2_44[8]}},a2_44}) <<< 0);
default:p3_44<=14'sd0;endcase end end end
logic signed [8:0] b1_45,a2_45;logic signed [13:0] p3_45;
always @(posedge clk)begin if(!rst_n)begin b1_45<=0;a2_45<=0;p3_45<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_45<=(-$signed({1'd0,x0[28]}) + $signed({1'd0,x0[29]}));
if(valid_pipe[1])a2_45<=mode_pipe[1]?$signed({1'd0,f1[45]}):b1_45;
if(valid_pipe[2])begin case(key2)
7'd0:p3_45<=($signed({{5{a2_45[8]}},a2_45}) <<< 4);
7'd4:p3_45<=($signed({{5{a2_45[8]}},a2_45}) <<< 1);
7'd33:p3_45<=-($signed({{5{a2_45[8]}},a2_45}) <<< 5);
7'd36,7'd67:p3_45<=-($signed({{5{a2_45[8]}},a2_45}) <<< 3);
7'd37,7'd40,7'd64:p3_45<=($signed({{5{a2_45[8]}},a2_45}) <<< 2);
7'd41,7'd80:p3_45<=($signed({{5{a2_45[8]}},a2_45}) <<< 0);
7'd83:p3_45<=-($signed({{5{a2_45[8]}},a2_45}) <<< 2);
default:p3_45<=14'sd0;endcase end end end
logic signed [9:0] b1_46,a2_46;logic signed [13:0] p3_46;
always @(posedge clk)begin if(!rst_n)begin b1_46<=0;a2_46<=0;p3_46<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_46<=((-$signed({2'd0,x0[27]}) + $signed({2'd0,x0[28]})) + ($signed({2'd0,x0[33]}) + -$signed({2'd0,x0[34]})));
if(valid_pipe[1])a2_46<=mode_pipe[1]?$signed({2'd0,f1[46]}):b1_46;
if(valid_pipe[2])begin case(key2)
7'd4:p3_46<=-($signed({{4{a2_46[9]}},a2_46}) <<< 1);
7'd33,7'd40,7'd83:p3_46<=($signed({{4{a2_46[9]}},a2_46}) <<< 1);
7'd36,7'd67:p3_46<=($signed({{4{a2_46[9]}},a2_46}) <<< 2);
7'd41:p3_46<=($signed({{4{a2_46[9]}},a2_46}) <<< 4);
7'd64,7'd66:p3_46<=-($signed({{4{a2_46[9]}},a2_46}) <<< 2);
7'd80,7'd81,7'd82:p3_46<=-($signed({{4{a2_46[9]}},a2_46}) <<< 0);
7'd65:p3_46<=($signed({{4{a2_46[9]}},a2_46}) <<< 3);
default:p3_46<=14'sd0;endcase end end end
logic signed [8:0] b1_47,a2_47;logic signed [12:0] p3_47;
always @(posedge clk)begin if(!rst_n)begin b1_47<=0;a2_47<=0;p3_47<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_47<=(-$signed({1'd0,x0[28]}) + $signed({1'd0,x0[34]}));
if(valid_pipe[1])a2_47<=mode_pipe[1]?$signed({1'd0,f1[47]}):b1_47;
if(valid_pipe[2])begin case(key2)
7'd0,7'd4,7'd65,7'd82:p3_47<=($signed({{4{a2_47[8]}},a2_47}) <<< 2);
7'd33,7'd64:p3_47<=-($signed({{4{a2_47[8]}},a2_47}) <<< 4);
7'd36,7'd41,7'd80:p3_47<=($signed({{4{a2_47[8]}},a2_47}) <<< 1);
7'd37,7'd67:p3_47<=($signed({{4{a2_47[8]}},a2_47}) <<< 4);
7'd40:p3_47<=-($signed({{4{a2_47[8]}},a2_47}) <<< 2);
7'd66:p3_47<=($signed({{4{a2_47[8]}},a2_47}) <<< 3);
7'd83:p3_47<=($signed({{4{a2_47[8]}},a2_47}) <<< 0);
default:p3_47<=13'sd0;endcase end end end
logic signed [9:0] b1_48,a2_48;logic signed [13:0] p3_48;
always @(posedge clk)begin if(!rst_n)begin b1_48<=0;a2_48<=0;p3_48<=0;end else begin
if(valid_pipe[0]&&!mode_pipe[0])b1_48<=(($signed({2'd0,x0[28]}) + -$signed({2'd0,x0[29]})) + (-$signed({2'd0,x0[34]}) + $signed({2'd0,x0[35]})));
if(valid_pipe[1])a2_48<=mode_pipe[1]?0:b1_48;
if(valid_pipe[2])begin case(key2)
7'd0:p3_48<=($signed({{4{a2_48[9]}},a2_48}) <<< 2);
7'd4:p3_48<=($signed({{4{a2_48[9]}},a2_48}) <<< 3);
7'd33:p3_48<=-($signed({{4{a2_48[9]}},a2_48}) <<< 4);
7'd36:p3_48<=-($signed({{4{a2_48[9]}},a2_48}) <<< 2);
7'd37:p3_48<=($signed({{4{a2_48[9]}},a2_48}) <<< 4);
7'd40,7'd41:p3_48<=-($signed({{4{a2_48[9]}},a2_48}) <<< 3);
default:p3_48<=14'sd0;endcase end end end
logic signed [17:0] h_0_0_0;
logic signed [17:0] h_0_0_1;
logic signed [17:0] h_0_1_0;
logic signed [17:0] h_0_1_1;
logic signed [17:0] h_0_2_0;
logic signed [17:0] h_0_2_1;
logic signed [17:0] h_0_3_0;
logic signed [17:0] h_0_3_1;
logic signed [15:0] h_1_0_0;
logic signed [15:0] h_1_0_1;
logic signed [15:0] h_1_1_0;
logic signed [15:0] h_1_1_1;
logic signed [15:0] h_1_2_0;
logic signed [15:0] h_1_2_1;
logic signed [15:0] h_1_3_0;
logic signed [15:0] h_1_3_1;
logic signed [16:0] h_2_0_0;
logic signed [16:0] h_2_0_1;
logic signed [16:0] h_2_1_0;
logic signed [16:0] h_2_1_1;
logic signed [16:0] h_2_2_0;
logic signed [16:0] h_2_2_1;
logic signed [14:0] h_3_0_0;
logic signed [14:0] h_3_0_1;
logic signed [14:0] h_3_1_0;
logic signed [14:0] h_3_1_1;
logic signed [14:0] h_3_2_0;
logic signed [14:0] h_3_2_1;
logic signed [19:0] z_0_0;
logic signed [18:0] z_0_1;
logic signed [18:0] z_0_2;
logic signed [18:0] z_0_3;
logic signed [17:0] z_1_0;
logic signed [17:0] z_1_1;
logic signed [17:0] z_1_2;
logic signed [17:0] z_1_3;
logic signed [17:0] z_2_0;
logic signed [17:0] z_2_1;
logic signed [17:0] z_2_2;
logic signed [17:0] z_2_3;
logic signed [15:0] z_3_0;
logic signed [15:0] z_3_1;
logic signed [15:0] z_3_2;
logic signed [15:0] z_3_3;
logic signed [13:0] fg4_0;
logic signed [14:0] fg4_1;
logic signed [14:0] fg4_2;
logic signed [14:0] fg4_3;
logic signed [14:0] fg4_4;
logic signed [13:0] fg4_5;
logic signed [14:0] fg4_6;
logic signed [14:0] fg4_7;
logic signed [13:0] fg4_8;
logic signed [14:0] fg4_9;
logic signed [14:0] fg4_10;
logic signed [14:0] fg4_11;
logic signed [13:0] fg4_12;
logic signed [13:0] fg4_13;
logic signed [14:0] fg4_14;
logic signed [13:0] fg4_15;
logic signed [16:0] fg5_0;
logic signed [15:0] fg5_1;
logic signed [16:0] fg5_2;
logic signed [15:0] fg5_3;
always @(posedge clk)begin if(!rst_n)begin
h_0_0_0<=0;
h_0_0_1<=0;
h_0_1_0<=0;
h_0_1_1<=0;
h_0_2_0<=0;
h_0_2_1<=0;
h_0_3_0<=0;
h_0_3_1<=0;
h_1_0_0<=0;
h_1_0_1<=0;
h_1_1_0<=0;
h_1_1_1<=0;
h_1_2_0<=0;
h_1_2_1<=0;
h_1_3_0<=0;
h_1_3_1<=0;
h_2_0_0<=0;
h_2_0_1<=0;
h_2_1_0<=0;
h_2_1_1<=0;
h_2_2_0<=0;
h_2_2_1<=0;
h_3_0_0<=0;
h_3_0_1<=0;
h_3_1_0<=0;
h_3_1_1<=0;
h_3_2_0<=0;
h_3_2_1<=0;
fg4_0<=0;
fg4_1<=0;
fg4_2<=0;
fg4_3<=0;
fg4_4<=0;
fg4_5<=0;
fg4_6<=0;
fg4_7<=0;
fg4_8<=0;
fg4_9<=0;
fg4_10<=0;
fg4_11<=0;
fg4_12<=0;
fg4_13<=0;
fg4_14<=0;
fg4_15<=0;
end else if(valid_pipe[3])begin if(!mode_pipe[3])begin
h_0_0_0<=($signed({{2{p3_0[15]}},p3_0}) + ($signed({{2{p3_1[15]}},p3_1}) + $signed({{2{p3_2[15]}},p3_2})));
h_0_0_1<=($signed({{2{p3_1[15]}},p3_1}) + (-$signed({{2{p3_2[15]}},p3_2}) + -$signed({{3{p3_3[14]}},p3_3})));
h_0_1_0<=($signed({{2{p3_4[15]}},p3_4}) + ($signed({{2{p3_5[15]}},p3_5}) + $signed({{3{p3_6[14]}},p3_6})));
h_0_1_1<=($signed({{2{p3_5[15]}},p3_5}) + (-$signed({{3{p3_6[14]}},p3_6}) + -$signed({{2{p3_7[15]}},p3_7})));
h_0_2_0<=($signed({{2{p3_8[15]}},p3_8}) + ($signed({{2{p3_9[15]}},p3_9}) + $signed({{2{p3_10[15]}},p3_10})));
h_0_2_1<=($signed({{2{p3_9[15]}},p3_9}) + (-$signed({{2{p3_10[15]}},p3_10}) + -$signed({{3{p3_11[14]}},p3_11})));
h_0_3_0<=($signed({{2{p3_12[15]}},p3_12}) + ($signed({{3{p3_13[14]}},p3_13}) + $signed({{2{p3_14[15]}},p3_14})));
h_0_3_1<=($signed({{3{p3_13[14]}},p3_13}) + (-$signed({{2{p3_14[15]}},p3_14}) + -$signed({{2{p3_15[15]}},p3_15})));
h_1_0_0<=($signed({{1{p3_16[14]}},p3_16}) + $signed({{1{p3_17[14]}},p3_17}));
h_1_0_1<=($signed({{1{p3_17[14]}},p3_17}) + $signed({{1{p3_18[14]}},p3_18}));
h_1_1_0<=($signed({{1{p3_19[14]}},p3_19}) + $signed({{1{p3_20[14]}},p3_20}));
h_1_1_1<=($signed({{1{p3_20[14]}},p3_20}) + $signed({{1{p3_21[14]}},p3_21}));
h_1_2_0<=($signed({{1{p3_22[14]}},p3_22}) + $signed({{1{p3_23[14]}},p3_23}));
h_1_2_1<=($signed({{1{p3_23[14]}},p3_23}) + $signed({{1{p3_24[14]}},p3_24}));
h_1_3_0<=($signed({{1{p3_25[14]}},p3_25}) + $signed({{1{p3_26[14]}},p3_26}));
h_1_3_1<=($signed({{1{p3_26[14]}},p3_26}) + $signed({{2{p3_27[13]}},p3_27}));
h_2_0_0<=($signed({{2{p3_28[14]}},p3_28}) + ($signed({{3{p3_29[13]}},p3_29}) + $signed({{2{p3_30[14]}},p3_30})));
h_2_0_1<=($signed({{3{p3_29[13]}},p3_29}) + (-$signed({{2{p3_30[14]}},p3_30}) + -$signed({{2{p3_31[14]}},p3_31})));
h_2_1_0<=($signed({{3{p3_32[13]}},p3_32}) + ($signed({{1{p3_33[15]}},p3_33}) + $signed({{3{p3_34[13]}},p3_34})));
h_2_1_1<=($signed({{1{p3_33[15]}},p3_33}) + (-$signed({{3{p3_34[13]}},p3_34}) + -$signed({{2{p3_35[14]}},p3_35})));
h_2_2_0<=($signed({{2{p3_36[14]}},p3_36}) + ($signed({{2{p3_37[14]}},p3_37}) + $signed({{2{p3_38[14]}},p3_38})));
h_2_2_1<=($signed({{2{p3_37[14]}},p3_37}) + (-$signed({{2{p3_38[14]}},p3_38}) + -$signed({{2{p3_39[14]}},p3_39})));
h_3_0_0<=($signed({{1{p3_40[13]}},p3_40}) + $signed({{1{p3_41[13]}},p3_41}));
h_3_0_1<=($signed({{1{p3_41[13]}},p3_41}) + $signed({{1{p3_42[13]}},p3_42}));
h_3_1_0<=($signed({{2{p3_43[12]}},p3_43}) + $signed({{1{p3_44[13]}},p3_44}));
h_3_1_1<=($signed({{1{p3_44[13]}},p3_44}) + $signed({{1{p3_45[13]}},p3_45}));
h_3_2_0<=($signed({{1{p3_46[13]}},p3_46}) + $signed({{2{p3_47[12]}},p3_47}));
h_3_2_1<=($signed({{2{p3_47[12]}},p3_47}) + $signed({{1{p3_48[13]}},p3_48}));
end else begin
fg4_0<=($signed(p3_0[13:0]) + ($signed(p3_1[13:0]) + $signed(p3_2[13:0])));
fg4_1<=($signed(p3_3) + ($signed(p3_4[14:0]) + $signed(p3_5[14:0])));
fg4_2<=($signed(p3_6) + ($signed(p3_7[14:0]) + $signed(p3_8[14:0])));
fg4_3<=($signed(p3_9[14:0]) + ($signed(p3_10[14:0]) + $signed(p3_11)));
fg4_4<=($signed(p3_12[14:0]) + ($signed(p3_13) + $signed(p3_14[14:0])));
fg4_5<=($signed(p3_15[13:0]) + ($signed(p3_16[13:0]) + $signed(p3_17[13:0])));
fg4_6<=($signed(p3_18) + ($signed(p3_19) + $signed(p3_20)));
fg4_7<=($signed(p3_21) + ($signed(p3_22) + $signed(p3_23)));
fg4_8<=($signed(p3_24[13:0]) + ($signed(p3_25[13:0]) + $signed(p3_26[13:0])));
fg4_9<=($signed({{1{p3_27[13]}},p3_27}) + ($signed(p3_28) + $signed({{1{p3_29[13]}},p3_29})));
fg4_10<=($signed(p3_30) + ($signed(p3_31) + $signed({{1{p3_32[13]}},p3_32})));
fg4_11<=($signed(p3_33[14:0]) + ($signed({{1{p3_34[13]}},p3_34}) + $signed(p3_35)));
fg4_12<=($signed(p3_36[13:0]) + ($signed(p3_37[13:0]) + $signed(p3_38[13:0])));
fg4_13<=($signed(p3_39[13:0]) + ($signed(p3_40) + $signed(p3_41)));
fg4_14<=($signed({{1{p3_42[13]}},p3_42}) + ($signed({{2{p3_43[12]}},p3_43}) + $signed({{1{p3_44[13]}},p3_44})));
fg4_15<=($signed(p3_45) + ($signed(p3_46) + $signed({{1{p3_47[12]}},p3_47})));
end end end
always @(posedge clk)begin if(!rst_n)begin
z_0_0<=0;
z_0_1<=0;
z_0_2<=0;
z_0_3<=0;
z_1_0<=0;
z_1_1<=0;
z_1_2<=0;
z_1_3<=0;
z_2_0<=0;
z_2_1<=0;
z_2_2<=0;
z_2_3<=0;
z_3_0<=0;
z_3_1<=0;
z_3_2<=0;
z_3_3<=0;
fg5_0<=0;
fg5_1<=0;
fg5_2<=0;
fg5_3<=0;
end else if(valid_pipe[4])begin if(!mode_pipe[4])begin
z_0_0<=($signed({{2{h_0_0_0[17]}},h_0_0_0}) + ($signed({{2{h_0_1_0[17]}},h_0_1_0}) + $signed({{2{h_0_2_0[17]}},h_0_2_0})));
z_0_1<=($signed({{1{h_0_0_1[17]}},h_0_0_1}) + ($signed({{1{h_0_1_1[17]}},h_0_1_1}) + $signed({{1{h_0_2_1[17]}},h_0_2_1})));
z_0_2<=($signed({{1{h_0_1_0[17]}},h_0_1_0}) + (-$signed({{1{h_0_2_0[17]}},h_0_2_0}) + -$signed({{1{h_0_3_0[17]}},h_0_3_0})));
z_0_3<=($signed({{1{h_0_1_1[17]}},h_0_1_1}) + (-$signed({{1{h_0_2_1[17]}},h_0_2_1}) + -$signed({{1{h_0_3_1[17]}},h_0_3_1})));
z_1_0<=($signed({{2{h_1_0_0[15]}},h_1_0_0}) + ($signed({{2{h_1_1_0[15]}},h_1_1_0}) + $signed({{2{h_1_2_0[15]}},h_1_2_0})));
z_1_1<=($signed({{2{h_1_0_1[15]}},h_1_0_1}) + ($signed({{2{h_1_1_1[15]}},h_1_1_1}) + $signed({{2{h_1_2_1[15]}},h_1_2_1})));
z_1_2<=($signed({{2{h_1_1_0[15]}},h_1_1_0}) + (-$signed({{2{h_1_2_0[15]}},h_1_2_0}) + -$signed({{2{h_1_3_0[15]}},h_1_3_0})));
z_1_3<=($signed({{2{h_1_1_1[15]}},h_1_1_1}) + (-$signed({{2{h_1_2_1[15]}},h_1_2_1}) + -$signed({{2{h_1_3_1[15]}},h_1_3_1})));
z_2_0<=($signed({{1{h_2_0_0[16]}},h_2_0_0}) + $signed({{1{h_2_1_0[16]}},h_2_1_0}));
z_2_1<=($signed({{1{h_2_0_1[16]}},h_2_0_1}) + $signed({{1{h_2_1_1[16]}},h_2_1_1}));
z_2_2<=($signed({{1{h_2_1_0[16]}},h_2_1_0}) + $signed({{1{h_2_2_0[16]}},h_2_2_0}));
z_2_3<=($signed({{1{h_2_1_1[16]}},h_2_1_1}) + $signed({{1{h_2_2_1[16]}},h_2_2_1}));
z_3_0<=($signed({{1{h_3_0_0[14]}},h_3_0_0}) + $signed({{1{h_3_1_0[14]}},h_3_1_0}));
z_3_1<=($signed({{1{h_3_0_1[14]}},h_3_0_1}) + $signed({{1{h_3_1_1[14]}},h_3_1_1}));
z_3_2<=($signed({{1{h_3_1_0[14]}},h_3_1_0}) + $signed({{1{h_3_2_0[14]}},h_3_2_0}));
z_3_3<=($signed({{1{h_3_1_1[14]}},h_3_1_1}) + $signed({{1{h_3_2_1[14]}},h_3_2_1}));
end else begin
fg5_0<=(($signed({{3{fg4_0[13]}},fg4_0}) + $signed({{2{fg4_1[14]}},fg4_1})) + ($signed({{2{fg4_2[14]}},fg4_2}) + $signed({{2{fg4_3[14]}},fg4_3})));
fg5_1<=(($signed({{1{fg4_4[14]}},fg4_4}) + $signed({{2{fg4_5[13]}},fg4_5})) + ($signed({{1{fg4_6[14]}},fg4_6}) + $signed({{1{fg4_7[14]}},fg4_7})));
fg5_2<=(($signed({{3{fg4_8[13]}},fg4_8}) + $signed({{2{fg4_9[14]}},fg4_9})) + ($signed({{2{fg4_10[14]}},fg4_10}) + $signed({{2{fg4_11[14]}},fg4_11})));
fg5_3<=(($signed({{2{fg4_12[13]}},fg4_12}) + $signed({{2{fg4_13[13]}},fg4_13})) + ($signed({{1{fg4_14[14]}},fg4_14}) + $signed({{2{fg4_15[13]}},fg4_15})));
end end end
always @(posedge clk)begin if(!rst_n)begin conv_y00<=0;conv_y01<=0;conv_y10<=0;conv_y11<=0;fc_sum<=0;end
else if(valid_pipe[5])begin if(!mode_pipe[5])begin
conv_y00<=((($signed({{12{z_0_0[19]}},z_0_0}) >>> 2) + ($signed({{14{z_1_0[17]}},z_1_0}) >>> 1)) + (($signed({{14{z_2_0[17]}},z_2_0}) >>> 1) + ($signed({{16{z_3_0[15]}},z_3_0}) >>> 0)));
conv_y01<=((($signed({{13{z_0_1[18]}},z_0_1}) >>> 2) + ($signed({{14{z_1_1[17]}},z_1_1}) >>> 1)) + (($signed({{14{z_2_1[17]}},z_2_1}) >>> 1) + ($signed({{16{z_3_1[15]}},z_3_1}) >>> 0)));
conv_y10<=((($signed({{13{z_0_2[18]}},z_0_2}) >>> 2) + ($signed({{14{z_1_2[17]}},z_1_2}) >>> 1)) + (($signed({{14{z_2_2[17]}},z_2_2}) >>> 1) + ($signed({{16{z_3_2[15]}},z_3_2}) >>> 0)));
conv_y11<=((($signed({{13{z_0_3[18]}},z_0_3}) >>> 2) + ($signed({{14{z_1_3[17]}},z_1_3}) >>> 1)) + (($signed({{14{z_2_3[17]}},z_2_3}) >>> 1) + ($signed({{16{z_3_3[15]}},z_3_3}) >>> 0)));
end else begin fc_sum<=(($signed({{15{fg5_0[16]}},fg5_0}) + $signed({{16{fg5_1[15]}},fg5_1})) + ($signed({{15{fg5_2[16]}},fg5_2}) + $signed({{16{fg5_3[15]}},fg5_3})));end end end
endmodule
