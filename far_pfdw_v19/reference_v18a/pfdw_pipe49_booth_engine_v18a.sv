`timescale 1ps/1ps

// =============================================================================
// PFDW V18A exact signed radix-4 Booth multiplier
// "correction-row Booth" power experiment.
//
// Difference from V17:
//   V17 generated negative partial products with wide unary negation:
//       -(A << s), -(2A << s)
//   V18A generates an inverted partial-product row plus a sparse correction bit:
//       (~A << s)  + (1 << s)
//   and accumulates all correction bits in one correction vector.
//
// This removes the per-negative-row +1 carry-propagation operation.
// No approximation, quantization, '*' operator, or generic divider is used.
// Pipeline boundaries outside this combinational multiplier are unchanged.
// =============================================================================
module pfdw_booth_mul_v18a #(
    parameter integer AW = 13,
    parameter integer BW = 10
) (
    input  logic signed [AW-1:0] a,
    input  logic signed [BW-1:0] b,
    output logic signed [AW+BW-1:0] p
);
    localparam integer NG   = (BW + 1) / 2;
    localparam integer ACCW = AW + BW + 2;

    // {sign extension of b, b, implicit b[-1]=0}
    logic [2*NG:0] yext;
    logic signed [ACCW-1:0] a_ext;

    // Inverted/positive Booth rows. The +1 terms for negative digits are
    // intentionally NOT performed here; they are collected in corr_vec.
    logic signed [ACCW-1:0] pp_core [0:NG-1];
    logic        [ACCW-1:0] corr_vec;

    integer i;
    logic [2:0] code;
    logic one_sel, two_sel, neg_sel;
    logic signed [ACCW-1:0] base_mag;

    always_comb begin
        yext = '0;
        yext[0] = 1'b0;
        for (i = 0; i < BW; i = i + 1)
            yext[i+1] = b[i];
        for (i = BW; i < 2*NG; i = i + 1)
            yext[i+1] = b[BW-1];

        a_ext   = {{(ACCW-AW){a[AW-1]}}, a};
        corr_vec = '0;

        for (i = 0; i < NG; i = i + 1) begin
            code = yext[(2*i) +: 3];

            // Radix-4 modified-Booth digit decode:
            // 001/010 -> +1
            // 011     -> +2
            // 100     -> -2
            // 101/110 -> -1
            // 000/111 ->  0
            one_sel = (code == 3'b001) || (code == 3'b010) ||
                      (code == 3'b101) || (code == 3'b110);
            two_sel = (code == 3'b011) || (code == 3'b100);
            neg_sel = (code == 3'b100) || (code == 3'b101) ||
                      (code == 3'b110);

            if (one_sel)
                base_mag = a_ext;
            else if (two_sel)
                base_mag = (a_ext <<< 1);
            else
                base_mag = '0;

            if (neg_sel) begin
                // -(base_mag << 2i)
                // = ((~base_mag) << 2i) + (1 << 2i)
                // The correction bit is kept separate to avoid a wide +1
                // carry propagation in every negative Booth row.
                pp_core[i] = ((~base_mag) <<< (2*i));
                corr_vec[2*i] = 1'b1;
            end else begin
                pp_core[i] = (base_mag <<< (2*i));
            end
        end
    end

    logic signed [ACCW-1:0] s01, s23, s45;
    logic signed [ACCW-1:0] row_sum;
    logic signed [ACCW-1:0] total;

    always_comb begin
        s01 = pp_core[0] + pp_core[1];
        s23 = pp_core[2] + pp_core[3];
        s45 = '0;

        if (NG == 4) begin
            row_sum = s01 + s23;
        end else if (NG == 5) begin
            row_sum = (s01 + s23) + pp_core[4];
        end else begin
            // V18A maximum BW=12 -> NG=6.
            s45 = pp_core[4] + pp_core[5];
            row_sum = (s01 + s23) + s45;
        end

        // One sparse correction-row addition replaces the per-negative-row
        // two's-complement +1 operations used implicitly by V17 unary '-'.
        total = row_sum + $signed(corr_vec);
        p = total[AW+BW-1:0];
    end
endmodule


// =============================================================================
// PFDW V18A range-proven 49-lane radix-4 Booth arithmetic engine
//
// V17 starts from V14 and preserves its scheduler, pipeline boundaries, exact lane widths and fixed-point behavior.
// V18A keeps the V17 exact radix-4 Booth datapath but replaces wide negative-row unary negation with sparse correction-row Booth generation.
//
// Goals preserved from V4:
//   - Break the long request-side path that dominated V2 timing.
//   - Preserve one-request/cycle throughput.
//   - Reuse all 49 lanes for convolution and 48 lanes for FC.
//   - Use explicit separable Winograd transforms and balanced-ish reductions.
//
// Pipeline (request sampled at P0, response produced at P6):
//   P0 : raw tile/kernel or 48 FC operands register
//   P1 : horizontal B/G transform (or FC pass-through)
//   P2 : vertical B/G transform -> 49 multiplier operands
//   P3 : 49 multipliers
//   P4 : horizontal inverse transform / 16x3 FC group sums
//   P5 : vertical inverse transform / 4 FC group sums
//   P6 : block merge / final FC sum -> response
// =============================================================================
module pfdw_pipe49_booth_engine_v18a (
    input  logic clk,
    input  logic rst_n,

    input  logic req_valid,
    input  logic req_is_fc,
    input  logic [15:0] req_tag,

    input  logic signed [11:0] conv_tile   [0:5][0:5],
    input  logic signed [7:0]  conv_kernel [0:4][0:4],

    input  logic signed [11:0] fc_a [0:47],
    input  logic signed [7:0]  fc_b [0:47],

    output logic rsp_valid,
    output logic rsp_is_fc,
    output logic [15:0] rsp_tag,
    output logic signed [31:0] conv_y00,
    output logic signed [31:0] conv_y01,
    output logic signed [31:0] conv_y10,
    output logic signed [31:0] conv_y11,
    output logic signed [39:0] fc_sum
);

    // -------------------------------------------------------------------------
    // Range-shaped 1-D transforms.
    //
    // Proven input ranges for this fixed-point network:
    //   pooled/input activation : 0 .. 2047  (12-bit signed nonnegative)
    //   raw kernel / FC weight  : -128 .. 127 (8-bit signed)
    //
    // Therefore the Winograd domains need only:
    //   B horizontal : 13 bits
    //   B vertical   : 14 bits
    //   G horizontal : 10 bits (9 bits for G2; unified by sign extension)
    //   G vertical   : 12 bits
    //
    // These widths are exact for this design; unlike approximate quantization,
    // no numerical information used by V3 is discarded.
    // -------------------------------------------------------------------------
    function automatic logic signed [12:0] b3_h12(
        input logic signed [11:0] x0,
        input logic signed [11:0] x1,
        input logic signed [11:0] x2,
        input logic signed [11:0] x3,
        input integer o
    );
        logic signed [12:0] a0, a1, a2, a3;
        begin
            a0 = {x0[11],x0}; a1 = {x1[11],x1};
            a2 = {x2[11],x2}; a3 = {x3[11],x3};
            case (o)
                0: b3_h12 = a0 - a2;
                1: b3_h12 = a1 + a2;
                2: b3_h12 = -a1 + a2;
                default: b3_h12 = a1 - a3;
            endcase
        end
    endfunction

    function automatic logic signed [12:0] b2_h12(
        input logic signed [11:0] x0,
        input logic signed [11:0] x1,
        input logic signed [11:0] x2,
        input integer o
    );
        logic signed [12:0] a0, a1, a2;
        begin
            a0 = {x0[11],x0}; a1 = {x1[11],x1}; a2 = {x2[11],x2};
            case (o)
                0: b2_h12 = a0 - a1;
                1: b2_h12 = a1;
                default: b2_h12 = -a1 + a2;
            endcase
        end
    endfunction

    function automatic logic signed [9:0] g3_h8(
        input logic signed [7:0] x0,
        input logic signed [7:0] x1,
        input logic signed [7:0] x2,
        input integer o
    );
        logic signed [9:0] a0, a1, a2;
        begin
            a0 = {{2{x0[7]}},x0}; a1 = {{2{x1[7]}},x1}; a2 = {{2{x2[7]}},x2};
            case (o)
                0: g3_h8 = a0 <<< 1;
                1: g3_h8 = a0 + a1 + a2;
                2: g3_h8 = a0 - a1 + a2;
                default: g3_h8 = a2 <<< 1;
            endcase
        end
    endfunction

    function automatic logic signed [8:0] g2_h8(
        input logic signed [7:0] x0,
        input logic signed [7:0] x1,
        input integer o
    );
        logic signed [8:0] a0, a1;
        begin
            a0 = {x0[7],x0}; a1 = {x1[7],x1};
            case (o)
                0: g2_h8 = a0;
                1: g2_h8 = a0 + a1;
                default: g2_h8 = a1;
            endcase
        end
    endfunction

    function automatic logic signed [9:0] g2_h8_sext10(
        input logic signed [7:0] x0,
        input logic signed [7:0] x1,
        input integer o
    );
        logic signed [8:0] t;
        begin
            t = g2_h8(x0,x1,o);
            g2_h8_sext10 = {t[8],t};
        end
    endfunction

    function automatic logic signed [13:0] b3_v13(
        input logic signed [12:0] x0,
        input logic signed [12:0] x1,
        input logic signed [12:0] x2,
        input logic signed [12:0] x3,
        input integer o
    );
        logic signed [13:0] a0, a1, a2, a3;
        begin
            a0 = {x0[12],x0}; a1 = {x1[12],x1};
            a2 = {x2[12],x2}; a3 = {x3[12],x3};
            case (o)
                0: b3_v13 = a0 - a2;
                1: b3_v13 = a1 + a2;
                2: b3_v13 = -a1 + a2;
                default: b3_v13 = a1 - a3;
            endcase
        end
    endfunction

    function automatic logic signed [13:0] b2_v13(
        input logic signed [12:0] x0,
        input logic signed [12:0] x1,
        input logic signed [12:0] x2,
        input integer o
    );
        logic signed [13:0] a0, a1, a2;
        begin
            a0 = {x0[12],x0}; a1 = {x1[12],x1}; a2 = {x2[12],x2};
            case (o)
                0: b2_v13 = a0 - a1;
                1: b2_v13 = a1;
                default: b2_v13 = -a1 + a2;
            endcase
        end
    endfunction

    function automatic logic signed [11:0] g3_v10(
        input logic signed [9:0] x0,
        input logic signed [9:0] x1,
        input logic signed [9:0] x2,
        input integer o
    );
        logic signed [11:0] a0, a1, a2;
        begin
            a0 = {{2{x0[9]}},x0}; a1 = {{2{x1[9]}},x1}; a2 = {{2{x2[9]}},x2};
            case (o)
                0: g3_v10 = a0 <<< 1;
                1: g3_v10 = a0 + a1 + a2;
                2: g3_v10 = a0 - a1 + a2;
                default: g3_v10 = a2 <<< 1;
            endcase
        end
    endfunction

    function automatic logic signed [11:0] g2_v10(
        input logic signed [9:0] x0,
        input logic signed [9:0] x1,
        input integer o
    );
        logic signed [11:0] a0, a1;
        begin
            a0 = {{2{x0[9]}},x0}; a1 = {{2{x1[9]}},x1};
            case (o)
                0: g2_v10 = a0;
                1: g2_v10 = a0 + a1;
                default: g2_v10 = a1;
            endcase
        end
    endfunction

    function automatic logic signed [25:0] a3_h26(
        input logic signed [25:0] x0,
        input logic signed [25:0] x1,
        input logic signed [25:0] x2,
        input logic signed [25:0] x3,
        input integer o
    );
        begin
            if (o == 0)
                a3_h26 = x0 + x1 + x2;
            else
                a3_h26 = x1 - x2 - x3;
        end
    endfunction

    function automatic logic signed [25:0] a2_h26(
        input logic signed [25:0] x0,
        input logic signed [25:0] x1,
        input logic signed [25:0] x2,
        input integer o
    );
        begin
            if (o == 0)
                a2_h26 = x0 + x1;
            else
                a2_h26 = x1 + x2;
        end
    endfunction

    function automatic logic signed [26:0] a3_v26(
        input logic signed [25:0] x0,
        input logic signed [25:0] x1,
        input logic signed [25:0] x2,
        input logic signed [25:0] x3,
        input integer o
    );
        logic signed [26:0] a0, a1, a2, a3;
        begin
            a0 = {x0[25],x0}; a1 = {x1[25],x1};
            a2 = {x2[25],x2}; a3 = {x3[25],x3};
            if (o == 0)
                a3_v26 = a0 + a1 + a2;
            else
                a3_v26 = a1 - a2 - a3;
        end
    endfunction

    function automatic logic signed [26:0] a2_v26(
        input logic signed [25:0] x0,
        input logic signed [25:0] x1,
        input logic signed [25:0] x2,
        input integer o
    );
        logic signed [26:0] a0, a1, a2;
        begin
            a0 = {x0[25],x0}; a1 = {x1[25],x1}; a2 = {x2[25],x2};
            if (o == 0)
                a2_v26 = a0 + a1;
            else
                a2_v26 = a1 + a2;
        end
    endfunction

    // -------------------------------------------------------------------------
    // P0: mode-overlaid request register.
    //
    // V6 stored Conv tile/kernel and FC activation/weight banks separately.
    // Conv and FC requests are mutually exclusive, therefore a single pair of
    // banks can safely carry both modes:
    //
    //   p0_a[0..47] : 12-bit activation storage
    //      Conv -> tile at [0..35]
    //      FC   -> 48 activations at [0..47]
    //
    //   p0_b[0..47] : 8-bit weight storage
    //      Conv -> kernel at [0..24]
    //      FC   -> 48 weights at [0..47]
    //
    // This removes 632 payload flip-flops versus V6 without changing a
    // pipeline boundary or request cadence.
    // -------------------------------------------------------------------------
    logic p0_valid, p0_is_fc;
    logic [15:0] p0_tag;
    logic signed [11:0] p0_a [0:47];
    logic signed [7:0]  p0_b [0:47];

    integer r0, c0, f0;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p0_valid <= 1'b0;
            p0_is_fc <= 1'b0;
            p0_tag   <= 16'd0;
        end else begin
            p0_valid <= req_valid;
            if (req_valid) begin
                p0_is_fc <= req_is_fc;
                p0_tag   <= req_tag;

                if (req_is_fc) begin
                    for (f0 = 0; f0 < 48; f0 = f0 + 1) begin
                        p0_a[f0] <= fc_a[f0];
                        p0_b[f0] <= fc_b[f0];
                    end
                end else begin
                    for (r0 = 0; r0 < 6; r0 = r0 + 1)
                        for (c0 = 0; c0 < 6; c0 = c0 + 1)
                            p0_a[r0*6+c0] <= conv_tile[r0][c0];

                    for (r0 = 0; r0 < 5; r0 = r0 + 1)
                        for (c0 = 0; c0 < 5; c0 = c0 + 1)
                            p0_b[r0*5+c0] <= conv_kernel[r0][c0];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // P1: mode-overlaid horizontal-transform register.
    //
    //   p1_a[49] : Conv activation transforms OR FC activations
    //   p1_b[48] : Conv kernel transforms     OR FC weights
    //
    // Conv horizontal activation outputs all fit signed 13 bits.
    // Conv horizontal kernel outputs fit signed 10 bits; G2 values are exact
    // sign extensions from their native 9-bit representation.
    //
    // Compared with V6's separate Conv+FC banks this removes another
    // 815 payload flip-flops while retaining the original P1 boundary.
    // -------------------------------------------------------------------------
    logic p1_valid, p1_is_fc;
    logic [15:0] p1_tag;
    logic signed [12:0] p1_a [0:48];
    logic signed [9:0]  p1_b [0:47];

    integer pr, po, pf;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p1_valid <= 1'b0;
            p1_is_fc <= 1'b0;
            p1_tag   <= 16'd0;
        end else begin
            p1_valid <= p0_valid;
            if (p0_valid) begin
                p1_is_fc <= p0_is_fc;
                p1_tag   <= p0_tag;

                if (p0_is_fc) begin
                    for (pf = 0; pf < 48; pf = pf + 1) begin
                        p1_a[pf] <= {p0_a[pf][11],p0_a[pf]};
                        p1_b[pf] <= {{2{p0_b[pf][7]}},p0_b[pf]};
                    end
                end else begin
                    // 3x3 block: activation lanes 0..15
                    for (pr = 0; pr < 4; pr = pr + 1)
                        for (po = 0; po < 4; po = po + 1)
                            p1_a[pr*4+po] <= b3_h12(
                                $signed(p0_a[pr*6+0]), $signed(p0_a[pr*6+1]),
                                $signed(p0_a[pr*6+2]), $signed(p0_a[pr*6+3]), po);

                    // 3x2 block: activation lanes 16..27
                    for (pr = 0; pr < 4; pr = pr + 1)
                        for (po = 0; po < 3; po = po + 1)
                            p1_a[16+pr*3+po] <= b2_h12(
                                $signed(p0_a[pr*6+3]), $signed(p0_a[pr*6+4]),
                                $signed(p0_a[pr*6+5]), po);

                    // 2x3 block: activation lanes 28..39
                    for (pr = 0; pr < 3; pr = pr + 1)
                        for (po = 0; po < 4; po = po + 1)
                            p1_a[28+pr*4+po] <= b3_h12(
                                $signed(p0_a[(pr+3)*6+0]), $signed(p0_a[(pr+3)*6+1]),
                                $signed(p0_a[(pr+3)*6+2]), $signed(p0_a[(pr+3)*6+3]), po);

                    // 2x2 block: activation lanes 40..48
                    for (pr = 0; pr < 3; pr = pr + 1)
                        for (po = 0; po < 3; po = po + 1)
                            p1_a[40+pr*3+po] <= b2_h12(
                                $signed(p0_a[(pr+3)*6+3]), $signed(p0_a[(pr+3)*6+4]),
                                $signed(p0_a[(pr+3)*6+5]), po);

                    // 3x3 kernel block: p1_b[0..11]
                    for (pr = 0; pr < 3; pr = pr + 1)
                        for (po = 0; po < 4; po = po + 1)
                            p1_b[pr*4+po] <= g3_h8(
                                $signed(p0_b[pr*5+0]), $signed(p0_b[pr*5+1]),
                                $signed(p0_b[pr*5+2]), po);

                    // 3x2 kernel block: p1_b[12..20]
                    for (pr = 0; pr < 3; pr = pr + 1)
                        for (po = 0; po < 3; po = po + 1)
                            p1_b[12+pr*3+po] <= g2_h8_sext10(
                                $signed(p0_b[pr*5+3]), $signed(p0_b[pr*5+4]), po);

                    // 2x3 kernel block: p1_b[21..28]
                    for (pr = 0; pr < 2; pr = pr + 1)
                        for (po = 0; po < 4; po = po + 1)
                            p1_b[21+pr*4+po] <= g3_h8(
                                $signed(p0_b[(pr+3)*5+0]), $signed(p0_b[(pr+3)*5+1]),
                                $signed(p0_b[(pr+3)*5+2]), po);

                    // 2x2 kernel block: p1_b[29..34]
                    for (pr = 0; pr < 2; pr = pr + 1)
                        for (po = 0; po < 3; po = po + 1)
                            p1_b[29+pr*3+po] <= g2_h8_sext10(
                                $signed(p0_b[(pr+3)*5+3]),
                                $signed(p0_b[(pr+3)*5+4]), po);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // P2/P3: exact lane-specific storage + heterogeneous multipliers.
    //
    // V6 used 49 identical:
    //      P2 : 14-bit activation + 12-bit weight registers
    //      P3 : 26-bit product registers
    //
    // V14 proves the exact signed interval required by every Winograd
    // coordinate.  FC sharing is preserved by never going below its exact
    // 12x8 operand requirement.
    //
    // P2 payload:
    //      V6  = 49*(14+12) = 1274 bits
    //      V14 = 1117 bits
    //
    // P3 product payload:
    //      V6  = 49*26 = 1274 bits
    //      V14 = 1068 bits
    //
    // Multiplier bit-product proxy:
    //      V6  = 8232
    //      V14 = 6274  (-23.8%)
    //
    // No approximation is introduced.  The 26-bit p3_p view below is only a
    // combinational sign extension of the physically narrow P3 registers so
    // that V6's inverse-transform equations remain bit-identical.
    // -------------------------------------------------------------------------

    function automatic integer lane_aw(input integer idx);
        begin
            case (idx)
                5: lane_aw = 14;
                17,23,26,32,34,35,41,43,44,45,47:
                    lane_aw = 12;
                default:
                    lane_aw = 13;
            endcase
        end
    endfunction

    function automatic integer lane_bw(input integer idx);
        begin
            case (idx)
                5,6,9,10:
                    lane_bw = 12;
                1,2,4,7,8,11,13,14,20,23,33,34:
                    lane_bw = 11;
                0,3,12,15,17,19,21,22,24,26,29,30,32,35,37,38,44:
                    lane_bw = 10;
                16,18,25,27,28,31,36,39,41,43,45,47:
                    lane_bw = 9;
                default:
                    lane_bw = 8;
            endcase
        end
    endfunction

    // Exact product widths from interval multiplication of each transformed
    // activation coordinate by its transformed kernel coordinate.
    function automatic integer lane_pw(input integer idx);
        begin
            case (idx)
                 0: lane_pw=22;  1: lane_pw=23;  2: lane_pw=23;  3: lane_pw=22;
                 4: lane_pw=23;  5: lane_pw=25;  6: lane_pw=24;  7: lane_pw=23;
                 8: lane_pw=23;  9: lane_pw=24; 10: lane_pw=24; 11: lane_pw=23;
                12: lane_pw=22; 13: lane_pw=23; 14: lane_pw=23; 15: lane_pw=22;
                16: lane_pw=21; 17: lane_pw=21; 18: lane_pw=21; 19: lane_pw=22;
                20: lane_pw=23; 21: lane_pw=22; 22: lane_pw=22; 23: lane_pw=22;
                24: lane_pw=22; 25: lane_pw=21; 26: lane_pw=21; 27: lane_pw=21;
                28: lane_pw=21; 29: lane_pw=22; 30: lane_pw=22; 31: lane_pw=21;
                32: lane_pw=21; 33: lane_pw=23; 34: lane_pw=22; 35: lane_pw=21;
                36: lane_pw=21; 37: lane_pw=22; 38: lane_pw=22; 39: lane_pw=21;
                40: lane_pw=20; 41: lane_pw=20; 42: lane_pw=20; 43: lane_pw=20;
                44: lane_pw=21; 45: lane_pw=20; 46: lane_pw=20; 47: lane_pw=20;
                default: lane_pw=20; // lane 48
            endcase
        end
    endfunction

    logic signed [13:0] p2_a_comb [0:48];
    logic signed [11:0] p2_b_comb [0:48];
    integer pj, pi;
    always_comb begin
        for (pi = 0; pi < 49; pi = pi + 1) begin
            p2_a_comb[pi] = 14'sd0;
            p2_b_comb[pi] = 12'sd0;
        end

        if (p1_is_fc) begin
            for (pi = 0; pi < 48; pi = pi + 1) begin
                p2_a_comb[pi] = {p1_a[pi][12],p1_a[pi]};
                p2_b_comb[pi] = {{2{p1_b[pi][9]}},p1_b[pi]};
            end
        end else begin
            // block 0: 4x4, lanes 0..15
            for (pj = 0; pj < 4; pj = pj + 1) begin
                for (pi = 0; pi < 4; pi = pi + 1) begin
                    p2_a_comb[pi*4+pj] = b3_v13(
                        p1_a[0*4+pj], p1_a[1*4+pj],
                        p1_a[2*4+pj], p1_a[3*4+pj], pi);
                    p2_b_comb[pi*4+pj] = g3_v10(
                        p1_b[0*4+pj], p1_b[1*4+pj],
                        p1_b[2*4+pj], pi);
                end
            end

            // block 1: 4x3, lanes 16..27
            for (pj = 0; pj < 3; pj = pj + 1) begin
                for (pi = 0; pi < 4; pi = pi + 1) begin
                    p2_a_comb[16+pi*3+pj] = b3_v13(
                        p1_a[16+0*3+pj], p1_a[16+1*3+pj],
                        p1_a[16+2*3+pj], p1_a[16+3*3+pj], pi);
                    p2_b_comb[16+pi*3+pj] = g3_v10(
                        p1_b[12+0*3+pj], p1_b[12+1*3+pj],
                        p1_b[12+2*3+pj], pi);
                end
            end

            // block 2: 3x4, lanes 28..39
            for (pj = 0; pj < 4; pj = pj + 1) begin
                for (pi = 0; pi < 3; pi = pi + 1) begin
                    p2_a_comb[28+pi*4+pj] = b2_v13(
                        p1_a[28+0*4+pj], p1_a[28+1*4+pj],
                        p1_a[28+2*4+pj], pi);
                    p2_b_comb[28+pi*4+pj] = g2_v10(
                        p1_b[21+0*4+pj], p1_b[21+1*4+pj], pi);
                end
            end

            // block 3: 3x3, lanes 40..48
            for (pj = 0; pj < 3; pj = pj + 1) begin
                for (pi = 0; pi < 3; pi = pi + 1) begin
                    p2_a_comb[40+pi*3+pj] = b2_v13(
                        p1_a[40+0*3+pj], p1_a[40+1*3+pj],
                        p1_a[40+2*3+pj], pi);
                    p2_b_comb[40+pi*3+pj] = g2_v10(
                        p1_b[29+0*3+pj], p1_b[29+1*3+pj], pi);
                end
            end
        end
    end

    logic p2_valid, p2_is_fc;
    logic [15:0] p2_tag;
    logic p3_valid, p3_is_fc;
    logic [15:0] p3_tag;

    // Combinational compatibility view used by the unchanged inverse transform.
    wire signed [25:0] p3_p [0:48];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p2_valid <= 1'b0;
            p2_is_fc <= 1'b0;
            p2_tag   <= 16'd0;
            p3_valid <= 1'b0;
            p3_is_fc <= 1'b0;
            p3_tag   <= 16'd0;
        end else begin
            p2_valid <= p1_valid;
            if (p1_valid) begin
                p2_is_fc <= p1_is_fc;
                p2_tag   <= p1_tag;
            end

            p3_valid <= p2_valid;
            if (p2_valid) begin
                p3_is_fc <= p2_is_fc;
                p3_tag   <= p2_tag;
            end
        end
    end

    genvar gm;
    generate
        for (gm = 0; gm < 49; gm = gm + 1) begin : G_V14_LANE
            localparam integer AW   = lane_aw(gm);
            localparam integer BW   = lane_bw(gm);
            localparam integer MULW = AW + BW;
            localparam integer PW   = lane_pw(gm);

            logic signed [AW-1:0] p2_a_q;
            logic signed [BW-1:0] p2_b_q;
            logic signed [PW-1:0] p3_p_q;
            wire  signed [MULW-1:0] mul_full;

            pfdw_booth_mul_v18a #(
                .AW(AW),
                .BW(BW)
            ) u_booth_mul (
                .a(p2_a_q),
                .b(p2_b_q),
                .p(mul_full)
            );

            assign p3_p[gm] = {{(26-PW){p3_p_q[PW-1]}},p3_p_q};

            always_ff @(posedge clk) begin
                if (p1_valid) begin
                    p2_a_q <= p2_a_comb[gm][AW-1:0];
                    p2_b_q <= p2_b_comb[gm][BW-1:0];
                end

                // Preserve V6's mode-aware operand isolation on unused FC lane48.
                if (p2_valid && ((!p2_is_fc) || (gm < 48)))
                    p3_p_q <= mul_full[PW-1:0];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // P4: horizontal inverse transform, or 16 sums of three FC products.
    //
    // V6 used signed 26-bit registers for every Conv P4 value. Exact interval
    // analysis permits block-specific physical widths:
    //    3x3 block : 26 bits (unchanged)
    //    3x2 block : 24 bits
    //    2x3 block : 24 bits
    //    2x2 block : 22 bits
    //
    // Sign-extended compatibility views keep P5 equations identical to V6.
    // -------------------------------------------------------------------------
    logic p4_valid, p4_is_fc;
    logic [15:0] p4_tag;

    logic signed [25:0] p4_h33 [0:3][0:1];
    logic signed [23:0] p4_h32_q [0:3][0:1];
    logic signed [23:0] p4_h23_q [0:2][0:1];
    logic signed [21:0] p4_h22_q [0:2][0:1];

    wire signed [25:0] p4_h32 [0:3][0:1];
    wire signed [25:0] p4_h23 [0:2][0:1];
    wire signed [25:0] p4_h22 [0:2][0:1];

    genvar e4r, e4c;
    generate
        for (e4r = 0; e4r < 4; e4r = e4r + 1) begin : G_P4_32_EXT_R
            for (e4c = 0; e4c < 2; e4c = e4c + 1) begin : G_P4_32_EXT_C
                assign p4_h32[e4r][e4c] =
                    {{2{p4_h32_q[e4r][e4c][23]}},p4_h32_q[e4r][e4c]};
            end
        end
        for (e4r = 0; e4r < 3; e4r = e4r + 1) begin : G_P4_SMALL_EXT_R
            for (e4c = 0; e4c < 2; e4c = e4c + 1) begin : G_P4_SMALL_EXT_C
                assign p4_h23[e4r][e4c] =
                    {{2{p4_h23_q[e4r][e4c][23]}},p4_h23_q[e4r][e4c]};
                assign p4_h22[e4r][e4c] =
                    {{4{p4_h22_q[e4r][e4c][21]}},p4_h22_q[e4r][e4c]};
            end
        end
    endgenerate

    logic signed [20:0] p4_fc_grp [0:15];

    integer p4r, p4g;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p4_valid <= 1'b0;
            p4_is_fc <= 1'b0;
            p4_tag   <= 16'd0;
        end else begin
            p4_valid <= p3_valid;
            if (p3_valid) begin
                p4_is_fc <= p3_is_fc;
                p4_tag   <= p3_tag;
                if (p3_is_fc) begin
                    for (p4g = 0; p4g < 16; p4g = p4g + 1)
                        p4_fc_grp[p4g] <=
                            {{2{p3_p[p4g*3][18]}},p3_p[p4g*3][18:0]}
                          + {{2{p3_p[p4g*3+1][18]}},p3_p[p4g*3+1][18:0]}
                          + {{2{p3_p[p4g*3+2][18]}},p3_p[p4g*3+2][18:0]};
                end else begin
                    for (p4r = 0; p4r < 4; p4r = p4r + 1) begin
                        p4_h33[p4r][0] <= a3_h26(
                            p3_p[p4r*4+0], p3_p[p4r*4+1],
                            p3_p[p4r*4+2], p3_p[p4r*4+3], 0);
                        p4_h33[p4r][1] <= a3_h26(
                            p3_p[p4r*4+0], p3_p[p4r*4+1],
                            p3_p[p4r*4+2], p3_p[p4r*4+3], 1);

                        p4_h32_q[p4r][0] <= a2_h26(
                            p3_p[16+p4r*3+0], p3_p[16+p4r*3+1],
                            p3_p[16+p4r*3+2], 0);
                        p4_h32_q[p4r][1] <= a2_h26(
                            p3_p[16+p4r*3+0], p3_p[16+p4r*3+1],
                            p3_p[16+p4r*3+2], 1);
                    end

                    for (p4r = 0; p4r < 3; p4r = p4r + 1) begin
                        p4_h23_q[p4r][0] <= a3_h26(
                            p3_p[28+p4r*4+0], p3_p[28+p4r*4+1],
                            p3_p[28+p4r*4+2], p3_p[28+p4r*4+3], 0);
                        p4_h23_q[p4r][1] <= a3_h26(
                            p3_p[28+p4r*4+0], p3_p[28+p4r*4+1],
                            p3_p[28+p4r*4+2], p3_p[28+p4r*4+3], 1);

                        p4_h22_q[p4r][0] <= a2_h26(
                            p3_p[40+p4r*3+0], p3_p[40+p4r*3+1],
                            p3_p[40+p4r*3+2], 0);
                        p4_h22_q[p4r][1] <= a2_h26(
                            p3_p[40+p4r*3+0], p3_p[40+p4r*3+1],
                            p3_p[40+p4r*3+2], 1);
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // P5: vertical inverse transform, or 4 groups of 12 FC products.
    //
    // Exact block result widths:
    //    block 0 (3x3) : 27 bits
    //    block 1 (3x2) : 25 bits
    //    block 2 (2x3) : 25 bits
    //    block 3 (2x2) : 23 bits
    //
    // p5_block is a 27-bit sign-extended wire view consumed by the unchanged
    // V6 P6 merge.
    // -------------------------------------------------------------------------
    logic p5_valid, p5_is_fc;
    logic [15:0] p5_tag;

    logic signed [26:0] p5_b0_q [0:3];
    logic signed [24:0] p5_b1_q [0:3];
    logic signed [24:0] p5_b2_q [0:3];
    logic signed [22:0] p5_b3_q [0:3];
    wire  signed [26:0] p5_block [0:15];

    genvar e5;
    generate
        for (e5 = 0; e5 < 4; e5 = e5 + 1) begin : G_P5_EXT
            assign p5_block[e5]    = p5_b0_q[e5];
            assign p5_block[4+e5]  = {{2{p5_b1_q[e5][24]}},p5_b1_q[e5]};
            assign p5_block[8+e5]  = {{2{p5_b2_q[e5][24]}},p5_b2_q[e5]};
            assign p5_block[12+e5] = {{4{p5_b3_q[e5][22]}},p5_b3_q[e5]};
        end
    endgenerate

    logic signed [22:0] p5_fc_grp4 [0:3];
    integer p5g;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            p5_valid <= 1'b0;
            p5_is_fc <= 1'b0;
            p5_tag   <= 16'd0;
        end else begin
            p5_valid <= p4_valid;
            if (p4_valid) begin
                p5_is_fc <= p4_is_fc;
                p5_tag   <= p4_tag;
                if (p4_is_fc) begin
                    for (p5g = 0; p5g < 4; p5g = p5g + 1)
                        p5_fc_grp4[p5g] <=
                            {{2{p4_fc_grp[p5g*4][20]}},p4_fc_grp[p5g*4]}
                          + {{2{p4_fc_grp[p5g*4+1][20]}},p4_fc_grp[p5g*4+1]}
                          + {{2{p4_fc_grp[p5g*4+2][20]}},p4_fc_grp[p5g*4+2]}
                          + {{2{p4_fc_grp[p5g*4+3][20]}},p4_fc_grp[p5g*4+3]};
                end else begin
                    // block 0 (A3 vertically)
                    p5_b0_q[0] <= a3_v26(p4_h33[0][0],p4_h33[1][0],p4_h33[2][0],p4_h33[3][0],0);
                    p5_b0_q[1] <= a3_v26(p4_h33[0][1],p4_h33[1][1],p4_h33[2][1],p4_h33[3][1],0);
                    p5_b0_q[2] <= a3_v26(p4_h33[0][0],p4_h33[1][0],p4_h33[2][0],p4_h33[3][0],1);
                    p5_b0_q[3] <= a3_v26(p4_h33[0][1],p4_h33[1][1],p4_h33[2][1],p4_h33[3][1],1);

                    // block 1 (A3 vertically)
                    p5_b1_q[0] <= a3_v26(p4_h32[0][0],p4_h32[1][0],p4_h32[2][0],p4_h32[3][0],0);
                    p5_b1_q[1] <= a3_v26(p4_h32[0][1],p4_h32[1][1],p4_h32[2][1],p4_h32[3][1],0);
                    p5_b1_q[2] <= a3_v26(p4_h32[0][0],p4_h32[1][0],p4_h32[2][0],p4_h32[3][0],1);
                    p5_b1_q[3] <= a3_v26(p4_h32[0][1],p4_h32[1][1],p4_h32[2][1],p4_h32[3][1],1);

                    // block 2 (A2 vertically)
                    p5_b2_q[0] <= a2_v26(p4_h23[0][0],p4_h23[1][0],p4_h23[2][0],0);
                    p5_b2_q[1] <= a2_v26(p4_h23[0][1],p4_h23[1][1],p4_h23[2][1],0);
                    p5_b2_q[2] <= a2_v26(p4_h23[0][0],p4_h23[1][0],p4_h23[2][0],1);
                    p5_b2_q[3] <= a2_v26(p4_h23[0][1],p4_h23[1][1],p4_h23[2][1],1);

                    // block 3 (A2 vertically)
                    p5_b3_q[0] <= a2_v26(p4_h22[0][0],p4_h22[1][0],p4_h22[2][0],0);
                    p5_b3_q[1] <= a2_v26(p4_h22[0][1],p4_h22[1][1],p4_h22[2][1],0);
                    p5_b3_q[2] <= a2_v26(p4_h22[0][0],p4_h22[1][0],p4_h22[2][0],1);
                    p5_b3_q[3] <= a2_v26(p4_h22[0][1],p4_h22[1][1],p4_h22[2][1],1);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // P6: block scaling/merge or final 48-term FC sum.
    // 29-bit merge temporaries and a 25-bit FC total are sufficient by range.
    // -------------------------------------------------------------------------
    logic signed [28:0] y0_comb, y1_comb, y2_comb, y3_comb;
    logic signed [24:0] fc48_comb;
    always_comb begin
        y0_comb = ({{2{p5_block[0][26]}},p5_block[0]}  >>> 2)
                + ({{2{p5_block[4][26]}},p5_block[4]}  >>> 1)
                + ({{2{p5_block[8][26]}},p5_block[8]}  >>> 1)
                +  {{2{p5_block[12][26]}},p5_block[12]};
        y1_comb = ({{2{p5_block[1][26]}},p5_block[1]}  >>> 2)
                + ({{2{p5_block[5][26]}},p5_block[5]}  >>> 1)
                + ({{2{p5_block[9][26]}},p5_block[9]}  >>> 1)
                +  {{2{p5_block[13][26]}},p5_block[13]};
        y2_comb = ({{2{p5_block[2][26]}},p5_block[2]}  >>> 2)
                + ({{2{p5_block[6][26]}},p5_block[6]}  >>> 1)
                + ({{2{p5_block[10][26]}},p5_block[10]} >>> 1)
                +  {{2{p5_block[14][26]}},p5_block[14]};
        y3_comb = ({{2{p5_block[3][26]}},p5_block[3]}  >>> 2)
                + ({{2{p5_block[7][26]}},p5_block[7]}  >>> 1)
                + ({{2{p5_block[11][26]}},p5_block[11]} >>> 1)
                +  {{2{p5_block[15][26]}},p5_block[15]};

        fc48_comb = {{2{p5_fc_grp4[0][22]}},p5_fc_grp4[0]}
                  + {{2{p5_fc_grp4[1][22]}},p5_fc_grp4[1]}
                  + {{2{p5_fc_grp4[2][22]}},p5_fc_grp4[2]}
                  + {{2{p5_fc_grp4[3][22]}},p5_fc_grp4[3]};
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0;
            rsp_is_fc <= 1'b0;
            rsp_tag   <= 16'd0;
            conv_y00  <= 32'sd0;
            conv_y01  <= 32'sd0;
            conv_y10  <= 32'sd0;
            conv_y11  <= 32'sd0;
            fc_sum    <= 40'sd0;
        end else begin
            rsp_valid <= p5_valid;
            if (p5_valid) begin
                rsp_is_fc <= p5_is_fc;
                rsp_tag   <= p5_tag;
                if (p5_is_fc) begin
                    fc_sum <= {{15{fc48_comb[24]}},fc48_comb};
                end else begin
                    conv_y00 <= {{3{y0_comb[28]}},y0_comb};
                    conv_y01 <= {{3{y1_comb[28]}},y1_comb};
                    conv_y10 <= {{3{y2_comb[28]}},y2_comb};
                    conv_y11 <= {{3{y3_comb[28]}},y3_comb};
                end
            end
        end
    end

endmodule
