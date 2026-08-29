// V20 W5 power-of-two OpenROAD synthesis wrapper. Keeps the official top module name "chip".
module chip(
    input clk,
    input rst_n,
    input [7:0] data_in,
    output [3:0] decision,
    output valid_out_6,

    input [0:199]  w_11,
    input [0:199]  w_12,
    input [0:199]  w_13,
    input [0:23]   b_1,
    input [0:23]   b_2,

    input [0:199]  w_211,
    input [0:199]  w_212,
    input [0:199]  w_213,
    input [0:199]  w_221,
    input [0:199]  w_222,
    input [0:199]  w_223,
    input [0:199]  w_231,
    input [0:199]  w_232,
    input [0:199]  w_233,

    input [0:3839] w_fc,
    input [0:79]   b_fc
);
    chip_pfdw_fc_v20_pow2 u_v20 (
        .clk(clk), .rst_n(rst_n), .data_in(data_in),
        .decision(decision), .valid_out_6(valid_out_6),
        .w_11(w_11), .w_12(w_12), .w_13(w_13), .b_1(b_1), .b_2(b_2),
        .w_211(w_211), .w_212(w_212), .w_213(w_213),
        .w_221(w_221), .w_222(w_222), .w_223(w_223),
        .w_231(w_231), .w_232(w_232), .w_233(w_233),
        .w_fc(w_fc), .b_fc(b_fc)
    );
endmodule
