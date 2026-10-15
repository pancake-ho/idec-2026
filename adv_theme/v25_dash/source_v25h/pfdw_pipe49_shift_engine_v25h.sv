// =============================================================================
// V25-H fixed-model PFDW multiplierless shared engine
//
// Generated from V25_H_export.zip:
//   Conv1 transformed coefficients : PoT1, W5 search point
//   Conv2 transformed coefficients : PoT1, W6 search point
//   FC coefficients                : SP2, W6 search point
//   Activations                    : unsigned 8-bit after pooling/quantization
//
// Key hardware changes from V24:
//   * removes all 49 Booth multipliers;
//   * removes the kernel G-transform datapath and all kernel pipeline registers;
//   * hard-wires the searched transformed coefficients;
//   * implements Conv products as zero/sign/constant-shift only;
//   * implements FC SP2 exactly as two temporal PoT1 passes (no lane adder);
//   * narrows activation-transform registers using exact 0..255 input bounds;
//   * narrows physical product registers lane-by-lane.
//
// External trained-weight ports remain on the chip wrapper for pin compatibility,
// but this fixed-model engine intentionally does not consume them.
// =============================================================================
`timescale 1ps/1ps

module pfdw_pipe49_shift_engine_v25h (
    input  logic clk,
    input  logic rst_n,

    input  logic req_valid,
    input  logic req_is_fc,
    input  logic [15:0] req_tag,

    input  logic signed [8:0] conv_tile [0:5][0:5],
    input  logic signed [8:0] fc_a [0:47],

    output logic rsp_valid,
    output logic rsp_is_fc,
    output logic [15:0] rsp_tag,
    output logic signed [19:0] conv_y00,
    output logic signed [19:0] conv_y01,
    output logic signed [19:0] conv_y10,
    output logic signed [19:0] conv_y11,
    output logic signed [15:0] fc_sum
);

    function automatic logic signed [9:0] b3_h9(
        input logic signed [8:0] x0,
        input logic signed [8:0] x1,
        input logic signed [8:0] x2,
        input logic signed [8:0] x3,
        input integer o
    );
        logic signed [9:0] a0,a1,a2,a3;
        begin
            a0={x0[8],x0}; a1={x1[8],x1};
            a2={x2[8],x2}; a3={x3[8],x3};
            case(o)
                0: b3_h9 = a0-a2;
                1: b3_h9 = a1+a2;
                2: b3_h9 = -a1+a2;
                default: b3_h9 = a1-a3;
            endcase
        end
    endfunction

    function automatic logic signed [9:0] b2_h9(
        input logic signed [8:0] x0,
        input logic signed [8:0] x1,
        input logic signed [8:0] x2,
        input integer o
    );
        logic signed [9:0] a0,a1,a2;
        begin
            a0={x0[8],x0}; a1={x1[8],x1}; a2={x2[8],x2};
            case(o)
                0: b2_h9 = a0-a1;
                1: b2_h9 = a1;
                default: b2_h9 = -a1+a2;
            endcase
        end
    endfunction

    function automatic logic signed [10:0] b3_v10(
        input logic signed [9:0] x0,
        input logic signed [9:0] x1,
        input logic signed [9:0] x2,
        input logic signed [9:0] x3,
        input integer o
    );
        logic signed [10:0] a0,a1,a2,a3;
        begin
            a0={x0[9],x0}; a1={x1[9],x1};
            a2={x2[9],x2}; a3={x3[9],x3};
            case(o)
                0: b3_v10 = a0-a2;
                1: b3_v10 = a1+a2;
                2: b3_v10 = -a1+a2;
                default: b3_v10 = a1-a3;
            endcase
        end
    endfunction

    function automatic logic signed [10:0] b2_v10(
        input logic signed [9:0] x0,
        input logic signed [9:0] x1,
        input logic signed [9:0] x2,
        input integer o
    );
        logic signed [10:0] a0,a1,a2;
        begin
            a0={x0[9],x0}; a1={x1[9],x1}; a2={x2[9],x2};
            case(o)
                0: b2_v10 = a0-a1;
                1: b2_v10 = a1;
                default: b2_v10 = -a1+a2;
            endcase
        end
    endfunction

    function automatic integer lane_aw(input integer idx);
        begin
            case (idx)
                17, 23, 26, 32, 34, 35, 41, 43, 44, 45, 47: lane_aw = 9;
                0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22, 24, 25, 27, 28, 29, 30, 31, 33, 36, 37, 38, 39, 40, 42, 46, 48: lane_aw = 10;
                5: lane_aw = 11;
                default: lane_aw = 10;
            endcase
        end
    endfunction

    function automatic integer lane_pw(input integer idx);
        begin
            case (idx)
                24, 34, 38, 40, 41, 42, 43, 45, 47, 48: lane_pw = 13;
                6, 9, 10, 14, 18, 22, 23, 29, 30, 32, 36, 44, 46: lane_pw = 14;
                1, 2, 8, 11, 13, 16, 17, 19, 21, 25, 26, 27, 28, 31, 33, 35, 37, 39: lane_pw = 15;
                0, 3, 4, 7, 12, 15, 20: lane_pw = 16;
                5: lane_pw = 17;
                default: lane_pw = 13;
            endcase
        end
    endfunction

    logic p0_valid, p0_is_fc;
    logic [15:0] p0_tag;
    logic signed [8:0] p0_a [0:47];
    integer r0,c0,f0;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            p0_valid<=1'b0; p0_is_fc<=1'b0; p0_tag<=16'd0;
        end else begin
            p0_valid<=req_valid;
            if(req_valid) begin
                p0_is_fc<=req_is_fc; p0_tag<=req_tag;
                if(req_is_fc) begin
                    for(f0=0;f0<48;f0=f0+1) p0_a[f0] <= fc_a[f0];
                end else begin
                    for(r0=0;r0<6;r0=r0+1)
                        for(c0=0;c0<6;c0=c0+1)
                            p0_a[r0*6+c0] <= conv_tile[r0][c0];
                end
            end
        end
    end

    logic p1_valid,p1_is_fc;
    logic [15:0] p1_tag;
    logic signed [9:0] p1_a [0:48];
    integer pr,po,pf;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            p1_valid<=1'b0; p1_is_fc<=1'b0; p1_tag<=16'd0;
        end else begin
            p1_valid<=p0_valid;
            if(p0_valid) begin
                p1_is_fc<=p0_is_fc; p1_tag<=p0_tag;
                if(p0_is_fc) begin
                    for(pf=0;pf<48;pf=pf+1)
                        p1_a[pf] <= {p0_a[pf][8],p0_a[pf]};
                    p1_a[48] <= 10'sd0;
                end else begin
                    for(pr=0;pr<4;pr=pr+1)
                        for(po=0;po<4;po=po+1)
                            p1_a[pr*4+po] <= b3_h9(p0_a[pr*6+0],p0_a[pr*6+1],p0_a[pr*6+2],p0_a[pr*6+3],po);
                    for(pr=0;pr<4;pr=pr+1)
                        for(po=0;po<3;po=po+1)
                            p1_a[16+pr*3+po] <= b2_h9(p0_a[pr*6+3],p0_a[pr*6+4],p0_a[pr*6+5],po);
                    for(pr=0;pr<3;pr=pr+1)
                        for(po=0;po<4;po=po+1)
                            p1_a[28+pr*4+po] <= b3_h9(p0_a[(pr+3)*6+0],p0_a[(pr+3)*6+1],p0_a[(pr+3)*6+2],p0_a[(pr+3)*6+3],po);
                    for(pr=0;pr<3;pr=pr+1)
                        for(po=0;po<3;po=po+1)
                            p1_a[40+pr*3+po] <= b2_h9(p0_a[(pr+3)*6+3],p0_a[(pr+3)*6+4],p0_a[(pr+3)*6+5],po);
                end
            end
        end
    end

    logic signed [10:0] p2_a_comb [0:48];
    integer pj,pi;
    always_comb begin
        for(pi=0;pi<49;pi=pi+1) p2_a_comb[pi]=11'sd0;
        if(p1_is_fc) begin
            for(pi=0;pi<48;pi=pi+1)
                p2_a_comb[pi] = {{1{p1_a[pi][9]}},p1_a[pi]};
        end else begin
            for(pj=0;pj<4;pj=pj+1)
                for(pi=0;pi<4;pi=pi+1)
                    p2_a_comb[pi*4+pj]=b3_v10(p1_a[0*4+pj],p1_a[1*4+pj],p1_a[2*4+pj],p1_a[3*4+pj],pi);
            for(pj=0;pj<3;pj=pj+1)
                for(pi=0;pi<4;pi=pi+1)
                    p2_a_comb[16+pi*3+pj]=b3_v10(p1_a[16+0*3+pj],p1_a[16+1*3+pj],p1_a[16+2*3+pj],p1_a[16+3*3+pj],pi);
            for(pj=0;pj<4;pj=pj+1)
                for(pi=0;pi<3;pi=pi+1)
                    p2_a_comb[28+pi*4+pj]=b2_v10(p1_a[28+0*4+pj],p1_a[28+1*4+pj],p1_a[28+2*4+pj],pi);
            for(pj=0;pj<3;pj=pj+1)
                for(pi=0;pi<3;pi=pi+1)
                    p2_a_comb[40+pi*3+pj]=b2_v10(p1_a[40+0*3+pj],p1_a[40+1*3+pj],p1_a[40+2*3+pj],pi);
        end
    end

    logic p2_valid,p2_is_fc,p3_valid,p3_is_fc;
    logic [15:0] p2_tag,p3_tag;
    wire signed [17:0] p3_p [0:48];

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            p2_valid<=1'b0; p2_is_fc<=1'b0; p2_tag<=16'd0;
            p3_valid<=1'b0; p3_is_fc<=1'b0; p3_tag<=16'd0;
        end else begin
            p2_valid<=p1_valid;
            if(p1_valid) begin p2_is_fc<=p1_is_fc; p2_tag<=p1_tag; end
            p3_valid<=p2_valid;
            if(p2_valid) begin p3_is_fc<=p2_is_fc; p3_tag<=p2_tag; end
        end
    end

    generate

        if (1) begin : G_LANE_0
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd16; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = -8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd64;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = -8'sd32;
                        4'b0101: coeff_term = -8'sd16;
                        4'b1000: coeff_term = -8'sd16;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[0] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[0][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (0 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_1
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd16; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd8; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd4; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd4; // term=1 class=6
                        5'd23: coeff_term = -8'sd4; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd4; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd32;
                        4'b0101: coeff_term = -8'sd32;
                        4'b1000: coeff_term = -8'sd8;
                        4'b1001: coeff_term = -8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[1] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[1][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (1 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_2
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd16; // term=0 class=1
                        5'd2: coeff_term = -8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd4; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd2; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = -8'sd2; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = -8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd4;
                        4'b0101: coeff_term = -8'sd16;
                        4'b1000: coeff_term = -8'sd8;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[2] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[2][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (2 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_3
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd8; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = -8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd4; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd0;
                        4'b0001: coeff_term = -8'sd64;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = -8'sd16;
                        4'b1000: coeff_term = 8'sd0;
                        4'b1001: coeff_term = -8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[3] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[3][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (3 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_4
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = -8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd8; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd16; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd2; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = -8'sd16;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd64;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd4;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = -8'sd32;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[4] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[4][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (4 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_5
            localparam integer AW = 11;
            localparam integer PW = 17;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = -8'sd2; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = -8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd64;
                        4'b0100: coeff_term = -8'sd32;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = -8'sd32;
                        4'b1001: coeff_term = -8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[5] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[5][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (5 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_6
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = -8'sd8;
                        4'b1000: coeff_term = -8'sd4;
                        4'b1001: coeff_term = 8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[6] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[6][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (6 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_7
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = -8'sd16; // term=0 class=5
                        5'd6: coeff_term = -8'sd16; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = -8'sd4; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd32;
                        4'b0001: coeff_term = -8'sd64;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = -8'sd2;
                        4'b1000: coeff_term = -8'sd16;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[7] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[7][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (7 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_8
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd2; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = -8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd4; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd2;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = -8'sd16;
                        4'b1000: coeff_term = -8'sd8;
                        4'b1001: coeff_term = -8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[8] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[8][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (8 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_9
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd8; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd8; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd2; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = -8'sd1;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd2;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = -8'sd8;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[9] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[9][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (9 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_10
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = -8'sd2; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = -8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = -8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd2;
                        2'd1: coeff_term = 8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = 8'sd2;
                        4'b0100: coeff_term = -8'sd2;
                        4'b0101: coeff_term = -8'sd8;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[10] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[10][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (10 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_11
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd8; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = -8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd8;
                        4'b0001: coeff_term = 8'sd2;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[11] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[11][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (11 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_12
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd8; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = -8'sd4; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd4; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = -8'sd16;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd64;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = 8'sd16;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = -8'sd16;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[12] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[12][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (12 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_13
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd8; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd16; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = -8'sd2; // term=0 class=5
                        5'd6: coeff_term = 8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = -8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd4;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = -8'sd8;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[13] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[13][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (13 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_14
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = -8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd2; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = -8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = 8'sd4;
                        4'b0100: coeff_term = 8'sd8;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[14] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[14][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (14 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_15
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd16; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd64;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[15] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[15][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (15 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_16
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = -8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = -8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = -8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd4; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = -8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd32;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = -8'sd8;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[16] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[16][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (16 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_17
            localparam integer AW = 9;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd8; // term=0 class=0
                        5'd1: coeff_term = -8'sd8; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd32;
                        2'd1: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd64;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd4;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = -8'sd2;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[17] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[17][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (17 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_18
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd4; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = -8'sd2; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd8;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = 8'sd4;
                        4'b1001: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[18] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[18][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (18 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_19
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd8; // term=0 class=0
                        5'd1: coeff_term = -8'sd8; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = -8'sd16; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd2; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd4; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd32;
                        2'd1: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd32;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[19] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[19][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (19 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_20
            localparam integer AW = 10;
            localparam integer PW = 16;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = -8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd64;
                        2'd1: coeff_term = -8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd16;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd32;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[20] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[20][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (20 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_21
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = -8'sd16; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = -8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd2; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[21] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[21][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (21 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_22
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd1; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = -8'sd4;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[22] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[22][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (22 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_23
            localparam integer AW = 9;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = -8'sd2; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = -8'sd2; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = -8'sd2; // term=1 class=8
                        5'd25: coeff_term = -8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd8;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = -8'sd4;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[23] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[23][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (23 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_24
            localparam integer AW = 10;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd4; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd4; // term=1 class=7
                        5'd24: coeff_term = -8'sd2; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = -8'sd1;
                        4'b1000: coeff_term = 8'sd1;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[24] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[24][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (24 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_25
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd16; // term=0 class=0
                        5'd1: coeff_term = -8'sd16; // term=0 class=1
                        5'd2: coeff_term = 8'sd0; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = -8'sd16; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd16; // term=0 class=6
                        5'd7: coeff_term = -8'sd16; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd8;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[25] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[25][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (25 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_26
            localparam integer AW = 9;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd16; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = -8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd16; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd4; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd32;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = -8'sd32;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = 8'sd64;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[26] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[26][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (26 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_27
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd8; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = -8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd4; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = -8'sd2; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = -8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd2; // term=1 class=6
                        5'd23: coeff_term = -8'sd2; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[27] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[27][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (27 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_28
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd0; // term=0 class=2
                        5'd3: coeff_term = 8'sd8; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = -8'sd16; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd2; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[28] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[28][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (28 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_29
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = -8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = -8'sd2; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd1; // term=1 class=3
                        5'd20: coeff_term = -8'sd4; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd2; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd2;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[29] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[29][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (29 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_30
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = 8'sd2; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd4; // term=0 class=5
                        5'd6: coeff_term = -8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd2;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = -8'sd4;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd2;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[30] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[30][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (30 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_31
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd8; // term=0 class=0
                        5'd1: coeff_term = 8'sd8; // term=0 class=1
                        5'd2: coeff_term = 8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = -8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd8;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[31] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[31][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (31 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_32
            localparam integer AW = 9;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd8; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd8; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd4; // term=0 class=8
                        5'd9: coeff_term = 8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd2; // term=1 class=8
                        5'd25: coeff_term = 8'sd4; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd32;
                        4'b0001: coeff_term = -8'sd32;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = -8'sd8;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[32] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[32][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (32 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_33
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = -8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = 8'sd8;
                        4'b0101: coeff_term = 8'sd32;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[33] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[33][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (33 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_34
            localparam integer AW = 9;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd4; // term=0 class=4
                        5'd5: coeff_term = -8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = -8'sd4; // term=1 class=2
                        5'd19: coeff_term = -8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd1; // term=1 class=8
                        5'd25: coeff_term = -8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = -8'sd16;
                        4'b0101: coeff_term = 8'sd2;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[34] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[34][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (34 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_35
            localparam integer AW = 9;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd8; // term=0 class=5
                        5'd6: coeff_term = -8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd4; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd4; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd2; // term=1 class=4
                        5'd21: coeff_term = 8'sd2; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd4; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd0;
                        4'b0001: coeff_term = 8'sd4;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd64;
                        4'b1000: coeff_term = 8'sd32;
                        4'b1001: coeff_term = -8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[35] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[35][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (35 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_36
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd4; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = 8'sd0; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd2; // term=0 class=6
                        5'd7: coeff_term = -8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd4; // term=0 class=8
                        5'd9: coeff_term = -8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd2; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd4;
                        4'b0001: coeff_term = -8'sd16;
                        4'b0100: coeff_term = 8'sd0;
                        4'b0101: coeff_term = -8'sd8;
                        4'b1000: coeff_term = 8'sd0;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[36] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[36][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (36 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_37
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = 8'sd0; // term=0 class=2
                        5'd3: coeff_term = 8'sd8; // term=0 class=3
                        5'd4: coeff_term = -8'sd8; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd2; // term=0 class=6
                        5'd7: coeff_term = -8'sd2; // term=0 class=7
                        5'd8: coeff_term = -8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd4; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = 8'sd2;
                        4'b0100: coeff_term = 8'sd16;
                        4'b0101: coeff_term = 8'sd32;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[37] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[37][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (37 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_38
            localparam integer AW = 10;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd8; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = -8'sd16; // term=0 class=5
                        5'd6: coeff_term = -8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd4; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd1;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd1;
                        4'b0101: coeff_term = 8'sd0;
                        4'b1000: coeff_term = -8'sd1;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[38] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[38][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (38 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_39
            localparam integer AW = 10;
            localparam integer PW = 15;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd2; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = -8'sd2; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = -8'sd2; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd1; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = 8'sd4;
                        4'b0100: coeff_term = 8'sd8;
                        4'b0101: coeff_term = 8'sd32;
                        4'b1000: coeff_term = 8'sd16;
                        4'b1001: coeff_term = -8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[39] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[39][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (39 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_40
            localparam integer AW = 10;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd16; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = -8'sd4; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd8; // term=0 class=8
                        5'd9: coeff_term = -8'sd16; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = -8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[40] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[40][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (40 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_41
            localparam integer AW = 9;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd8; // term=0 class=0
                        5'd1: coeff_term = 8'sd2; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd2; // term=0 class=3
                        5'd4: coeff_term = -8'sd8; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd8; // term=0 class=9
                        5'd16: coeff_term = -8'sd2; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = -8'sd4; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd2; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = -8'sd2; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd0;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = -8'sd8;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = 8'sd4;
                        4'b1001: coeff_term = -8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[41] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[41][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (41 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_42
            localparam integer AW = 10;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = -8'sd4; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd2; // term=1 class=7
                        5'd24: coeff_term = -8'sd1; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd0;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd4;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = 8'sd0;
                        4'b0101: coeff_term = 8'sd4;
                        4'b1000: coeff_term = -8'sd4;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[42] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[42][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (42 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_43
            localparam integer AW = 9;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd8; // term=0 class=0
                        5'd1: coeff_term = -8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd4; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = -8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd8; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = -8'sd2; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = -8'sd1; // term=1 class=4
                        5'd21: coeff_term = -8'sd2; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd1; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = -8'sd4;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd8;
                        4'b1001: coeff_term = -8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[43] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[43][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (43 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_44
            localparam integer AW = 9;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd0; // term=0 class=0
                        5'd1: coeff_term = 8'sd4; // term=0 class=1
                        5'd2: coeff_term = 8'sd0; // term=0 class=2
                        5'd3: coeff_term = -8'sd4; // term=0 class=3
                        5'd4: coeff_term = 8'sd2; // term=0 class=4
                        5'd5: coeff_term = 8'sd0; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd2; // term=0 class=7
                        5'd8: coeff_term = 8'sd2; // term=0 class=8
                        5'd9: coeff_term = -8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd0; // term=1 class=0
                        5'd17: coeff_term = 8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = -8'sd1; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd16;
                        2'd1: coeff_term = 8'sd32;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = -8'sd8;
                        4'b0100: coeff_term = 8'sd8;
                        4'b0101: coeff_term = 8'sd32;
                        4'b1000: coeff_term = 8'sd4;
                        4'b1001: coeff_term = -8'sd2;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[44] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[44][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (44 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_45
            localparam integer AW = 9;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd4; // term=0 class=0
                        5'd1: coeff_term = -8'sd2; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = 8'sd0; // term=0 class=4
                        5'd5: coeff_term = 8'sd8; // term=0 class=5
                        5'd6: coeff_term = -8'sd8; // term=0 class=6
                        5'd7: coeff_term = 8'sd0; // term=0 class=7
                        5'd8: coeff_term = -8'sd8; // term=0 class=8
                        5'd9: coeff_term = 8'sd0; // term=0 class=9
                        5'd16: coeff_term = -8'sd2; // term=1 class=0
                        5'd17: coeff_term = -8'sd1; // term=1 class=1
                        5'd18: coeff_term = 8'sd0; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = -8'sd1; // term=1 class=5
                        5'd22: coeff_term = -8'sd2; // term=1 class=6
                        5'd23: coeff_term = 8'sd0; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd16;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = 8'sd8;
                        4'b1000: coeff_term = -8'sd4;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[45] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[45][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (45 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_46
            localparam integer AW = 10;
            localparam integer PW = 14;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = -8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = -8'sd8; // term=0 class=2
                        5'd3: coeff_term = 8'sd8; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd8; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = 8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = 8'sd2; // term=0 class=9
                        5'd16: coeff_term = -8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = 8'sd1; // term=1 class=2
                        5'd19: coeff_term = 8'sd4; // term=1 class=3
                        5'd20: coeff_term = -8'sd2; // term=1 class=4
                        5'd21: coeff_term = 8'sd0; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = 8'sd1; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd8;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd0;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = 8'sd8;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd2;
                        4'b1001: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[46] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[46][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (46 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_47
            localparam integer AW = 9;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        5'd0: coeff_term = 8'sd2; // term=0 class=0
                        5'd1: coeff_term = 8'sd0; // term=0 class=1
                        5'd2: coeff_term = -8'sd4; // term=0 class=2
                        5'd3: coeff_term = 8'sd0; // term=0 class=3
                        5'd4: coeff_term = -8'sd4; // term=0 class=4
                        5'd5: coeff_term = 8'sd2; // term=0 class=5
                        5'd6: coeff_term = 8'sd0; // term=0 class=6
                        5'd7: coeff_term = -8'sd4; // term=0 class=7
                        5'd8: coeff_term = 8'sd0; // term=0 class=8
                        5'd9: coeff_term = -8'sd2; // term=0 class=9
                        5'd16: coeff_term = 8'sd1; // term=1 class=0
                        5'd17: coeff_term = 8'sd0; // term=1 class=1
                        5'd18: coeff_term = -8'sd2; // term=1 class=2
                        5'd19: coeff_term = 8'sd0; // term=1 class=3
                        5'd20: coeff_term = 8'sd0; // term=1 class=4
                        5'd21: coeff_term = 8'sd1; // term=1 class=5
                        5'd22: coeff_term = 8'sd0; // term=1 class=6
                        5'd23: coeff_term = -8'sd2; // term=1 class=7
                        5'd24: coeff_term = 8'sd0; // term=1 class=8
                        5'd25: coeff_term = 8'sd0; // term=1 class=9
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd8;
                        2'd1: coeff_term = 8'sd16;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = 8'sd16;
                        4'b0101: coeff_term = 8'sd16;
                        4'b1000: coeff_term = 8'sd2;
                        4'b1001: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[47] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[47][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (47 < 48)))
                    p3_p_q <= prod_comb;
            end
        end

        if (1) begin : G_LANE_48
            localparam integer AW = 10;
            localparam integer PW = 13;
            logic signed [AW-1:0] p2_a_q;
            logic signed [PW-1:0] p3_p_q;
            logic signed [PW-1:0] prod_comb;
            logic signed [7:0] coeff_term;
            wire signed [PW-1:0] a_ext =
                {{(PW-AW){p2_a_q[AW-1]}}, p2_a_q};

            always_comb begin
                coeff_term = 8'sd0;
                if (p2_is_fc) begin
                    case ({p2_tag[4],p2_tag[3:0]})
                        default: coeff_term = 8'sd0;
                    endcase
                end else if (!p2_tag[15]) begin
                    case (p2_tag[3:2])
                        2'd0: coeff_term = 8'sd4;
                        2'd1: coeff_term = 8'sd4;
                        default: coeff_term = 8'sd0;
                    endcase
                end else begin
                    case ({p2_tag[3:2],p2_tag[1:0]})
                        4'b0000: coeff_term = 8'sd8;
                        4'b0001: coeff_term = 8'sd0;
                        4'b0100: coeff_term = 8'sd4;
                        4'b0101: coeff_term = 8'sd2;
                        4'b1000: coeff_term = 8'sd0;
                        4'b1001: coeff_term = 8'sd0;
                        default: coeff_term = 8'sd0;
                    endcase
                end

                case (coeff_term)
                    -8'sd64: prod_comb = -($signed(a_ext) <<< 6);
                    -8'sd32: prod_comb = -($signed(a_ext) <<< 5);
                    -8'sd16: prod_comb = -($signed(a_ext) <<< 4);
                    -8'sd8: prod_comb = -($signed(a_ext) <<< 3);
                    -8'sd4: prod_comb = -($signed(a_ext) <<< 2);
                    -8'sd2: prod_comb = -($signed(a_ext) <<< 1);
                    -8'sd1: prod_comb = -$signed(a_ext);
                    8'sd0: prod_comb = '0;
                    8'sd1: prod_comb = $signed(a_ext);
                    8'sd2: prod_comb = ($signed(a_ext) <<< 1);
                    8'sd4: prod_comb = ($signed(a_ext) <<< 2);
                    8'sd8: prod_comb = ($signed(a_ext) <<< 3);
                    8'sd16: prod_comb = ($signed(a_ext) <<< 4);
                    8'sd32: prod_comb = ($signed(a_ext) <<< 5);
                    8'sd64: prod_comb = ($signed(a_ext) <<< 6);
                    default: prod_comb = '0;
                endcase
            end

            assign p3_p[48] = {{(18-PW){p3_p_q[PW-1]}}, p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid)
                    p2_a_q <= p2_a_comb[48][AW-1:0];
                if (p2_valid && ((!p2_is_fc) || (48 < 48)))
                    p3_p_q <= prod_comb;
            end
        end
    endgenerate

    logic p4_valid,p4_is_fc;
    logic [15:0] p4_tag;
    logic signed [17:0] p4_h33 [0:3][0:1];
    logic signed [16:0] p4_h32 [0:3][0:1];
    logic signed [16:0] p4_h23 [0:2][0:1];
    logic signed [14:0] p4_h22 [0:2][0:1];
    logic signed [14:0] p4_fc_grp [0:15];

    function automatic logic signed [17:0] a3_h18(
        input logic signed [17:0] x0,x1,x2,x3,input integer o);
        logic signed [19:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1)+$signed(x2);
            else     t=$signed(x1)-$signed(x2)-$signed(x3);
            a3_h18=t[17:0];
        end
    endfunction
    function automatic logic signed [16:0] a2_h17(
        input logic signed [17:0] x0,x1,x2,input integer o);
        logic signed [19:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1);
            else     t=$signed(x1)+$signed(x2);
            a2_h17=t[16:0];
        end
    endfunction
    function automatic logic signed [16:0] a3_h17(
        input logic signed [17:0] x0,x1,x2,x3,input integer o);
        logic signed [19:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1)+$signed(x2);
            else     t=$signed(x1)-$signed(x2)-$signed(x3);
            a3_h17=t[16:0];
        end
    endfunction
    function automatic logic signed [14:0] a2_h15(
        input logic signed [17:0] x0,x1,x2,input integer o);
        logic signed [19:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1);
            else     t=$signed(x1)+$signed(x2);
            a2_h15=t[14:0];
        end
    endfunction

    integer p4r,p4g;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            p4_valid<=1'b0; p4_is_fc<=1'b0; p4_tag<=16'd0;
        end else begin
            p4_valid<=p3_valid;
            if(p3_valid) begin
                p4_is_fc<=p3_is_fc; p4_tag<=p3_tag;
                if(p3_is_fc) begin
                    for(p4g=0;p4g<16;p4g=p4g+1)
                        p4_fc_grp[p4g] <=
                            $signed(p3_p[p4g*3]) +
                            $signed(p3_p[p4g*3+1]) +
                            $signed(p3_p[p4g*3+2]);
                end else begin
                    for(p4r=0;p4r<4;p4r=p4r+1) begin
                        p4_h33[p4r][0] <= a3_h18(p3_p[p4r*4+0],p3_p[p4r*4+1],p3_p[p4r*4+2],p3_p[p4r*4+3],0);
                        p4_h33[p4r][1] <= a3_h18(p3_p[p4r*4+0],p3_p[p4r*4+1],p3_p[p4r*4+2],p3_p[p4r*4+3],1);
                        p4_h32[p4r][0] <= a2_h17(p3_p[16+p4r*3+0],p3_p[16+p4r*3+1],p3_p[16+p4r*3+2],0);
                        p4_h32[p4r][1] <= a2_h17(p3_p[16+p4r*3+0],p3_p[16+p4r*3+1],p3_p[16+p4r*3+2],1);
                    end
                    for(p4r=0;p4r<3;p4r=p4r+1) begin
                        p4_h23[p4r][0] <= a3_h17(p3_p[28+p4r*4+0],p3_p[28+p4r*4+1],p3_p[28+p4r*4+2],p3_p[28+p4r*4+3],0);
                        p4_h23[p4r][1] <= a3_h17(p3_p[28+p4r*4+0],p3_p[28+p4r*4+1],p3_p[28+p4r*4+2],p3_p[28+p4r*4+3],1);
                        p4_h22[p4r][0] <= a2_h15(p3_p[40+p4r*3+0],p3_p[40+p4r*3+1],p3_p[40+p4r*3+2],0);
                        p4_h22[p4r][1] <= a2_h15(p3_p[40+p4r*3+0],p3_p[40+p4r*3+1],p3_p[40+p4r*3+2],1);
                    end
                end
            end
        end
    end

    logic p5_valid,p5_is_fc;
    logic [15:0] p5_tag;
    logic signed [18:0] p5_b0 [0:3];
    logic signed [17:0] p5_b1 [0:3];
    logic signed [17:0] p5_b2 [0:3];
    logic signed [15:0] p5_b3 [0:3];
    logic signed [15:0] p5_fc_grp4 [0:3];

    function automatic logic signed [18:0] a3_v19(
        input logic signed [17:0] x0,x1,x2,x3,input integer o);
        logic signed [20:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1)+$signed(x2);
            else     t=$signed(x1)-$signed(x2)-$signed(x3);
            a3_v19=t[18:0];
        end
    endfunction
    function automatic logic signed [17:0] a3_v18_from17(
        input logic signed [16:0] x0,x1,x2,x3,input integer o);
        logic signed [20:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1)+$signed(x2);
            else     t=$signed(x1)-$signed(x2)-$signed(x3);
            a3_v18_from17=t[17:0];
        end
    endfunction
    function automatic logic signed [17:0] a2_v18_from17(
        input logic signed [16:0] x0,x1,x2,input integer o);
        logic signed [19:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1);
            else     t=$signed(x1)+$signed(x2);
            a2_v18_from17=t[17:0];
        end
    endfunction
    function automatic logic signed [15:0] a2_v16_from15(
        input logic signed [14:0] x0,x1,x2,input integer o);
        logic signed [18:0] t;
        begin
            if(o==0) t=$signed(x0)+$signed(x1);
            else     t=$signed(x1)+$signed(x2);
            a2_v16_from15=t[15:0];
        end
    endfunction

    integer p5g;
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            p5_valid<=1'b0; p5_is_fc<=1'b0; p5_tag<=16'd0;
        end else begin
            p5_valid<=p4_valid;
            if(p4_valid) begin
                p5_is_fc<=p4_is_fc; p5_tag<=p4_tag;
                if(p4_is_fc) begin
                    for(p5g=0;p5g<4;p5g=p5g+1)
                        p5_fc_grp4[p5g] <=
                            $signed({p4_fc_grp[p5g*4][14],p4_fc_grp[p5g*4]}) +
                            $signed({p4_fc_grp[p5g*4+1][14],p4_fc_grp[p5g*4+1]}) +
                            $signed({p4_fc_grp[p5g*4+2][14],p4_fc_grp[p5g*4+2]}) +
                            $signed({p4_fc_grp[p5g*4+3][14],p4_fc_grp[p5g*4+3]});
                end else begin
                    p5_b0[0] <= a3_v19(p4_h33[0][0],p4_h33[1][0],p4_h33[2][0],p4_h33[3][0],0);
                    p5_b0[1] <= a3_v19(p4_h33[0][1],p4_h33[1][1],p4_h33[2][1],p4_h33[3][1],0);
                    p5_b0[2] <= a3_v19(p4_h33[0][0],p4_h33[1][0],p4_h33[2][0],p4_h33[3][0],1);
                    p5_b0[3] <= a3_v19(p4_h33[0][1],p4_h33[1][1],p4_h33[2][1],p4_h33[3][1],1);

                    p5_b1[0] <= a3_v18_from17(p4_h32[0][0],p4_h32[1][0],p4_h32[2][0],p4_h32[3][0],0);
                    p5_b1[1] <= a3_v18_from17(p4_h32[0][1],p4_h32[1][1],p4_h32[2][1],p4_h32[3][1],0);
                    p5_b1[2] <= a3_v18_from17(p4_h32[0][0],p4_h32[1][0],p4_h32[2][0],p4_h32[3][0],1);
                    p5_b1[3] <= a3_v18_from17(p4_h32[0][1],p4_h32[1][1],p4_h32[2][1],p4_h32[3][1],1);

                    p5_b2[0] <= a2_v18_from17(p4_h23[0][0],p4_h23[1][0],p4_h23[2][0],0);
                    p5_b2[1] <= a2_v18_from17(p4_h23[0][1],p4_h23[1][1],p4_h23[2][1],0);
                    p5_b2[2] <= a2_v18_from17(p4_h23[0][0],p4_h23[1][0],p4_h23[2][0],1);
                    p5_b2[3] <= a2_v18_from17(p4_h23[0][1],p4_h23[1][1],p4_h23[2][1],1);

                    p5_b3[0] <= a2_v16_from15(p4_h22[0][0],p4_h22[1][0],p4_h22[2][0],0);
                    p5_b3[1] <= a2_v16_from15(p4_h22[0][1],p4_h22[1][1],p4_h22[2][1],0);
                    p5_b3[2] <= a2_v16_from15(p4_h22[0][0],p4_h22[1][0],p4_h22[2][0],1);
                    p5_b3[3] <= a2_v16_from15(p4_h22[0][1],p4_h22[1][1],p4_h22[2][1],1);
                end
            end
        end
    end

    logic signed [21:0] y0_comb,y1_comb,y2_comb,y3_comb;
    logic signed [16:0] fc48_wide;
    logic signed [15:0] fc48_comb;
    always_comb begin
        y0_comb = ($signed({{3{p5_b0[0][18]}},p5_b0[0]}) >>> 2)
                + ($signed({{4{p5_b1[0][17]}},p5_b1[0]}) >>> 1)
                + ($signed({{4{p5_b2[0][17]}},p5_b2[0]}) >>> 1)
                +  $signed({{6{p5_b3[0][15]}},p5_b3[0]});
        y1_comb = ($signed({{3{p5_b0[1][18]}},p5_b0[1]}) >>> 2)
                + ($signed({{4{p5_b1[1][17]}},p5_b1[1]}) >>> 1)
                + ($signed({{4{p5_b2[1][17]}},p5_b2[1]}) >>> 1)
                +  $signed({{6{p5_b3[1][15]}},p5_b3[1]});
        y2_comb = ($signed({{3{p5_b0[2][18]}},p5_b0[2]}) >>> 2)
                + ($signed({{4{p5_b1[2][17]}},p5_b1[2]}) >>> 1)
                + ($signed({{4{p5_b2[2][17]}},p5_b2[2]}) >>> 1)
                +  $signed({{6{p5_b3[2][15]}},p5_b3[2]});
        y3_comb = ($signed({{3{p5_b0[3][18]}},p5_b0[3]}) >>> 2)
                + ($signed({{4{p5_b1[3][17]}},p5_b1[3]}) >>> 1)
                + ($signed({{4{p5_b2[3][17]}},p5_b2[3]}) >>> 1)
                +  $signed({{6{p5_b3[3][15]}},p5_b3[3]});

        fc48_wide = $signed({p5_fc_grp4[0][15],p5_fc_grp4[0]})
                    + $signed({p5_fc_grp4[1][15],p5_fc_grp4[1]})
                    + $signed({p5_fc_grp4[2][15],p5_fc_grp4[2]})
                    + $signed({p5_fc_grp4[3][15],p5_fc_grp4[3]});
        fc48_comb = fc48_wide[15:0];
    end

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            rsp_valid<=1'b0; rsp_is_fc<=1'b0; rsp_tag<=16'd0;
            conv_y00<=20'sd0; conv_y01<=20'sd0;
            conv_y10<=20'sd0; conv_y11<=20'sd0;
            fc_sum<=16'sd0;
        end else begin
            rsp_valid<=p5_valid;
            if(p5_valid) begin
                rsp_is_fc<=p5_is_fc; rsp_tag<=p5_tag;
                if(p5_is_fc)
                    fc_sum <= fc48_comb;
                else begin
                    conv_y00 <= y0_comb[19:0];
                    conv_y01 <= y1_comb[19:0];
                    conv_y10 <= y2_comb[19:0];
                    conv_y11 <= y3_comb[19:0];
                end
            end
        end
    end
endmodule

