// =============================================================================
// V25-H controller: multiplierless fixed-model PFDW accelerator
//
// Search point: W566 / A88 / C(pot1,pot1,sp2) / T(16,8,8) / M67.
//   * Conv1: original output channel 0 removed; original channels 1/2 kept.
//   * Conv2: all three output channels kept, but only the two surviving Conv1
//            channels are consumed.
//   * Conv1/Conv2 transformed coefficients use single signed powers of two.
//   * FC SP2 coefficients are evaluated as two temporal PoT1 passes.
//   * Post-pool feature maps are stored at 8 bits.
//   * External trained-weight ports are retained only for interface compatibility;
//     this fixed-model implementation embeds the searched coefficients. Bias ports
//     remain live inputs.
//
// The controller preserves the V24 streaming/overlap architecture where useful,
// while adapting request counts, tags and writeback to the pruned two-channel
// Conv1 representation.
// =============================================================================
`timescale 1ps/1ps

// Architecture notes:
//   - A persistent 6x6 Conv1 sliding window avoids a wide dynamic line-buffer mux.
//   - Conv1 has two physical output channels and Conv2 consumes two input channels.
//   - Conv1/Conv2 share the 49-lane fixed-coefficient shift engine.
//   - Conv1/Conv2 overlap is retained; FC begins after all 48 fmap2 values commit.
//   - FC uses two temporal passes per class to realize SP2 without per-lane adders.
//   - The FC final score uses an exact reduced-width bias/carry formulation to avoid
//     the V24 external-bias -> 20-bit-adder -> argmax critical path.
//
module chip_pfdw_fc_v25h (
    input  logic clk,
    input  logic rst_n,
    input  logic [7:0] data_in,
    output logic [3:0] decision,
    output logic valid_out_6,

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

    localparam ST_STREAM = 2'd0;
    localparam ST_FC     = 2'd1;
    localparam ST_DONE   = 2'd2;
    logic [1:0] state;

    // -------------------------------------------------------------------------
    // External input stream storage.
    // Explicit row/col/slot counters replace /28, %28 and %7 address arithmetic.
    // -------------------------------------------------------------------------
    logic [7:0] linebuf [0:6][0:27];
    logic [9:0] pixels_stored;
    logic       capture_primed;
    logic [4:0] cap_row, cap_col;
    logic [2:0] cap_slot;

    // Conv1 local 6x6 sliding window.
    // The engine sees only this register bank, not a dynamic 7x28 column mux.
    logic        [7:0]  c1_window [0:5][0:5];
    logic               c1_window_valid;
    logic [4:0]         c1_new_col;  // two entering columns for next stride-2 tile

    // Pool outputs. V6 retains only seven logical fmap1 rows at a time.
    // V25-H stores post-ReLU pooled values directly as unsigned 8-bit data.
    // Conv1 keeps two physical channels: 2 x 7 x 12 x 8 = 1344 payload bits.
    logic        [7:0] fmap1_ring [0:1][0:6][0:11];
    logic        [7:0] fmap2 [0:2][0:3][0:3];

    // -------------------------------------------------------------------------
    // Conv1 progress.
    // c1_base_slot = (2*c1_issue_pr) mod 7, maintained incrementally.
    // -------------------------------------------------------------------------
    logic [3:0] c1_issue_pr, c1_issue_pc;
    logic       c1_issue_oc;
    logic [2:0] c1_base_slot;
    logic [8:0] c1_issue_count;
    logic [8:0] c1_commit_count;

    // Conv1 writeback pipeline. WB0 registers the four quantized values; the
    // following cycle performs only 4-way max/ReLU and commits to fmap1_ring.
    logic c1_wb_valid;
    logic [2:0] c1_wb_slot;
    logic [3:0] c1_wb_pc;
    logic       c1_wb_oc;
    logic signed [11:0] c1_wb_q00, c1_wb_q01, c1_wb_q10, c1_wb_q11;

    // Conv2 progress.
    logic [1:0] c2_issue_pr, c2_issue_pc;
    logic [1:0] c2_issue_oc;
    logic       c2_issue_ic;
    // Physical ring slot corresponding to logical Conv2 window start row
    // (2*c2_issue_pr) mod 7. Updated only when Conv2 advances to next row.
    logic [2:0] c2_base_slot;
    logic [7:0] c2_issue_count;
    logic [7:0] c2_rsp_count;
    logic signed [19:0] c2_acc00, c2_acc01, c2_acc10, c2_acc11;

    // Conv2 writeback pipeline. the prior critical path ran directly from the
    // engine output register through final channel accumulation, quantization,
    // max-pool/ReLU and into fmap2. V4 cuts that cone into three short stages.
    logic c2_wb0_valid, c2_wb1_valid;
    logic [1:0] c2_wb0_pr, c2_wb0_pc, c2_wb0_oc;
    logic [1:0] c2_wb1_pr, c2_wb1_pc, c2_wb1_oc;
    logic signed [19:0] c2_wb0_sum00, c2_wb0_sum01, c2_wb0_sum10, c2_wb0_sum11;
    logic signed [11:0] c2_wb1_q00, c2_wb1_q01, c2_wb1_q10, c2_wb1_q11;
    logic [5:0] c2_commit_count;

    // FC progress: two temporal PoT1 requests per class implement SP2 exactly.
    logic [3:0] fc_issue_class;
    logic [4:0] fc_issue_count;
    logic       fc_issue_term;
    logic signed [15:0] fc_term0_sum;
    logic signed [11:0] best_score;
    logic [3:0] best_idx;

    // -------------------------------------------------------------------------
    // Helpers.
    // -------------------------------------------------------------------------
    // Layer-specific scale restoration from the searched V25-H point.
    localparam integer C1_RESTORE_SHIFT = 3; // INT8 -> W5
    localparam integer C2_RESTORE_SHIFT = 5; // A11->A8 (3) + INT8->W6 (2)
    localparam integer FC_RESTORE_SHIFT = 5; // A11->A8 (3) + INT8->W6 (2)

    // Conv1 physical channel 0/1 corresponds to original channel 1/2.
    function automatic logic signed [7:0] get_b1(input integer phys_oc);
        begin
            case (phys_oc)
                0: get_b1 = $signed(b_1[8+:8]);
                1: get_b1 = $signed(b_1[16+:8]);
                default: get_b1 = 8'sd0;
            endcase
        end
    endfunction

    function automatic logic signed [7:0] get_b2(input integer oc);
        begin
            case (oc)
                0: get_b2 = $signed(b_2[0+:8]);
                1: get_b2 = $signed(b_2[8+:8]);
                2: get_b2 = $signed(b_2[16+:8]);
                default: get_b2 = 8'sd0;
            endcase
        end
    endfunction

    function automatic logic signed [7:0] get_fcb(input integer cls);
        get_fcb = $signed(b_fc[(8*cls)+:8]);
    endfunction

    function automatic logic signed [11:0] conv1_q(
        input logic signed [31:0] raw,
        input logic signed [7:0] bias8
    );
        logic signed [19:0] t20;
        logic signed [11:0] shr12;
        logic signed [11:0] b12;
        logic signed [12:0] add13;
        begin
            t20   = raw[19:0];
            shr12 = $signed(t20) >>> 8;
            b12   = {{4{bias8[7]}},bias8};
            add13 = $signed(shr12) + $signed(b12);
            conv1_q = add13[11:0];
        end
    endfunction

    function automatic logic signed [11:0] conv2_q(
        input logic signed [19:0] sum20,
        input logic signed [7:0] bias8
    );
        logic signed [13:0] t14;
        logic signed [12:0] pre13;
        logic signed [11:0] b12;
        logic signed [13:0] add14;
        begin
            t14   = sum20[19:6];
            pre13 = $signed(t14[13:1]);
            b12   = {{4{bias8[7]}},bias8};
            add14 = $signed(pre13) + $signed(b12);
            conv2_q = add14[11:0];
        end
    endfunction

    function automatic logic signed [11:0] max4_relu(
        input logic signed [11:0] a,
        input logic signed [11:0] b,
        input logic signed [11:0] c,
        input logic signed [11:0] d
    );
        logic signed [11:0] m0, m1, m;
        begin
            m0 = (a >= b) ? a : b;
            m1 = (c >= d) ? c : d;
            m  = (m0 >= m1) ? m0 : m1;
            max4_relu = (m > 0) ? m : 12'sd0;
        end
    endfunction

    // Exact A8 storage used by the V25 search model:
    // pool/ReLU is still performed in the 12-bit domain, then arithmetic >>3.
    function automatic logic [7:0] max4_relu_a8(
        input logic signed [11:0] a,
        input logic signed [11:0] b,
        input logic signed [11:0] c,
        input logic signed [11:0] d
    );
        logic signed [11:0] m0, m1, m;
        begin
            m0 = (a >= b) ? a : b;
            m1 = (c >= d) ? c : d;
            m  = (m0 >= m1) ? m0 : m1;
            if (m > 0)
                max4_relu_a8 = m[10:3];
            else
                max4_relu_a8 = 8'd0;
        end
    endfunction

    function automatic [2:0] add_mod7(
        input logic [2:0] base,
        input integer off
    );
        integer tmp;
        begin
            tmp = base + off;
            if (tmp >= 7) tmp = tmp - 7;
            add_mod7 = tmp[2:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Shared V6 engine.
    // -------------------------------------------------------------------------
    logic req_valid, req_is_fc;
    logic [15:0] req_tag;
    logic signed [8:0] req_tile [0:5][0:5];
    logic signed [8:0] req_fc_a [0:47];

    logic rsp_valid, rsp_is_fc;
    logic [15:0] rsp_tag;
    logic signed [19:0] rsp_y00, rsp_y01, rsp_y10, rsp_y11;
    logic signed [15:0] rsp_fc_sum;

    pfdw_pipe49_shift_engine_v25h u_engine (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_is_fc(req_is_fc), .req_tag(req_tag),
        .conv_tile(req_tile), .fc_a(req_fc_a),
        .rsp_valid(rsp_valid), .rsp_is_fc(rsp_is_fc), .rsp_tag(rsp_tag),
        .conv_y00(rsp_y00), .conv_y01(rsp_y01),
        .conv_y10(rsp_y10), .conv_y11(rsp_y11),
        .fc_sum(rsp_fc_sum)
    );

    // -------------------------------------------------------------------------
    // Dependency checks.
    // -------------------------------------------------------------------------
    logic c1_tile_ready;
    integer c2_required_commit_idx;
    logic c2_data_ready;

    always_comb begin
        // V6 issues Conv1 only from the local sliding window. The row-start
        // window becomes valid on the same capture edge that makes V6's first
        // tile ready; subsequent horizontal tiles are shifted in-place.
        c1_tile_ready = (c1_issue_count < 9'd288) && c1_window_valid;

        // fmap1 is produced row-major, col-major, then two physical channels.
        // Physical ic0/ic1 map to original Conv1 channels 1/2.
        c2_required_commit_idx = (((c2_issue_pr*2 + 5) * 12
                                 + (c2_issue_pc*2 + 5)) * 2
                                 + c2_issue_ic);
        c2_data_ready = (c2_issue_count < 8'd96)
                     && (c1_commit_count > c2_required_commit_idx);
    end

    // -------------------------------------------------------------------------
    // Dependency-aware request scheduler.
    // Conv1 gets priority so the 7-line input buffer safety proof remains the
    // same as V2. Conv2 uses only otherwise-idle Conv1 cycles until C1 finishes.
    // -------------------------------------------------------------------------
    integer rr, cc, kk, lane, ch, pos;
    logic issue_c1, issue_c2;
    always_comb begin
        req_valid = 1'b0;
        req_is_fc = 1'b0;
        req_tag   = 16'd0;
        issue_c1  = 1'b0;
        issue_c2  = 1'b0;
        kk = 0;
        ch = 0;
        pos = 0;

        for (rr = 0; rr < 6; rr = rr + 1)
            for (cc = 0; cc < 6; cc = cc + 1)
                req_tile[rr][cc] = 9'sd0;

        for (lane = 0; lane < 48; lane = lane + 1) begin
            req_fc_a[lane] = 9'sd0;
        end

        if (state == ST_STREAM) begin
            if (c1_tile_ready) begin
                issue_c1 = 1'b1;
                req_valid = 1'b1;
                req_is_fc = 1'b0;
                req_tag = {1'b0, 3'b000, c1_issue_pr, c1_issue_pc, 1'b0, c1_issue_oc, 2'b00};

                // Fixed/local wiring: no c1_issue_pc-driven 28-column mux.
                for (rr = 0; rr < 6; rr = rr + 1)
                    for (cc = 0; cc < 6; cc = cc + 1)
                        req_tile[rr][cc] = {1'b0,c1_window[rr][cc]};
            end else if (c2_data_ready) begin
                issue_c2 = 1'b1;
                req_valid = 1'b1;
                req_is_fc = 1'b0;
                req_tag = {1'b1, 3'b000, {2'b00,c2_issue_pr},
                           {2'b00,c2_issue_pc}, c2_issue_oc, 1'b0, c2_issue_ic};

                for (rr = 0; rr < 6; rr = rr + 1)
                    for (cc = 0; cc < 6; cc = cc + 1)
                        req_tile[rr][cc] = {1'b0, fmap1_ring[c2_issue_ic]
                            [add_mod7(c2_base_slot,rr)][c2_issue_pc*2+cc]};
            end
        end else if (state == ST_FC && fc_issue_count < 5'd20) begin
            req_valid = 1'b1;
            req_is_fc = 1'b1;
            req_tag = {11'd0,fc_issue_term,fc_issue_class};

            for (lane = 0; lane < 48; lane = lane + 1) begin
                ch  = lane / 16;
                pos = lane % 16;
                req_fc_a[lane] = {1'b0,fmap2[ch][pos/4][pos%4]};
            end
        end
    end

    // -------------------------------------------------------------------------
    // Response decode / fixed-point behavior.
    // -------------------------------------------------------------------------
    wire rsp_layer = rsp_tag[15];
    wire [3:0] rsp_pr = rsp_tag[11:8];
    wire [3:0] rsp_pc = rsp_tag[7:4];
    wire [1:0] rsp_oc = rsp_tag[3:2];
    wire [1:0] rsp_ic = rsp_tag[1:0];
    wire [3:0] rsp_fc_class = rsp_tag[3:0];
    wire       rsp_fc_term  = rsp_tag[4];

    logic signed [11:0] rsp_c1q00, rsp_c1q01, rsp_c1q10, rsp_c1q11;
    logic signed [19:0] rsp_eng20_00, rsp_eng20_01, rsp_eng20_10, rsp_eng20_11;
    logic signed [11:0] c2_wb0_q00, c2_wb0_q01, c2_wb0_q10, c2_wb0_q11;
    logic signed [11:0] fc_score_now;
    logic signed [16:0] fc_class_sum;
    logic [13:0] fc_sum_mod14;
    logic [11:0] fc_base12;
    logic [1:0]  fc_rem2;
    logic signed [8:0] fc_low9;

    always_comb begin
        rsp_c1q00 = conv1_q($signed(rsp_y00) <<< C1_RESTORE_SHIFT,get_b1(rsp_oc));
        rsp_c1q01 = conv1_q($signed(rsp_y01) <<< C1_RESTORE_SHIFT,get_b1(rsp_oc));
        rsp_c1q10 = conv1_q($signed(rsp_y10) <<< C1_RESTORE_SHIFT,get_b1(rsp_oc));
        rsp_c1q11 = conv1_q($signed(rsp_y11) <<< C1_RESTORE_SHIFT,get_b1(rsp_oc));

        rsp_eng20_00 = $signed(rsp_y00[19:0]) <<< C2_RESTORE_SHIFT;
        rsp_eng20_01 = $signed(rsp_y01[19:0]) <<< C2_RESTORE_SHIFT;
        rsp_eng20_10 = $signed(rsp_y10[19:0]) <<< C2_RESTORE_SHIFT;
        rsp_eng20_11 = $signed(rsp_y11[19:0]) <<< C2_RESTORE_SHIFT;

        // WB1 quantization is now isolated from engine-output accumulation.
        c2_wb0_q00 = conv2_q(c2_wb0_sum00,get_b2(c2_wb0_oc));
        c2_wb0_q01 = conv2_q(c2_wb0_sum01,get_b2(c2_wb0_oc));
        c2_wb0_q10 = conv2_q(c2_wb0_sum10,get_b2(c2_wb0_oc));
        c2_wb0_q11 = conv2_q(c2_wb0_sum11,get_b2(c2_wb0_oc));

        // Exact reduced FC score datapath for restore shift=5.
        // Original semantics:
        //   score = signed_slice(wrap20((sum<<5)+bias),18,7)
        // Only sum[13:0], the two low remainder bits and a {-1,0,+1}
        // correction are required. This removes V24's 20-bit bias adder and
        // breaks the old b_fc -> best_score critical path without 80 bias FFs.
        fc_class_sum = $signed({fc_term0_sum[15],fc_term0_sum})
                     + $signed({rsp_fc_sum[15],rsp_fc_sum});
        fc_sum_mod14 = fc_class_sum[13:0];
        fc_base12 = fc_sum_mod14[13:2];
        fc_rem2 = fc_sum_mod14[1:0];
        fc_low9 = $signed({2'b00,fc_rem2,5'b00000}) + $signed(get_fcb(rsp_fc_class));
        if (fc_low9 < 0)
            fc_score_now = $signed(fc_base12) - 12'sd1;
        else if (fc_low9 >= 9'sd128)
            fc_score_now = $signed(fc_base12) + 12'sd1;
        else
            fc_score_now = $signed(fc_base12);
    end

    // -------------------------------------------------------------------------
    // Main controller.
    // -------------------------------------------------------------------------
    integer c1wr, c1wc;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_STREAM;
            pixels_stored <= 10'd0;
            capture_primed <= 1'b0;
            cap_row <= 0;
            cap_col <= 0;
            cap_slot <= 0;
            c1_window_valid <= 1'b0;
            c1_new_col <= 5'd6;

            c1_issue_pr <= 0; c1_issue_pc <= 0; c1_issue_oc <= 0;
            c1_base_slot <= 0;
            c1_issue_count <= 0; c1_commit_count <= 0;
            c1_wb_valid <= 1'b0;
            c1_wb_slot <= 0; c1_wb_pc <= 0; c1_wb_oc <= 0;
            c1_wb_q00 <= 0; c1_wb_q01 <= 0;
            c1_wb_q10 <= 0; c1_wb_q11 <= 0;

            c2_issue_pr <= 0; c2_issue_pc <= 0;
            c2_issue_oc <= 0; c2_issue_ic <= 0;
            c2_base_slot <= 0;
            c2_issue_count <= 0; c2_rsp_count <= 0;
            c2_acc00 <= 0; c2_acc01 <= 0; c2_acc10 <= 0; c2_acc11 <= 0;

            c2_wb0_valid <= 1'b0;
            c2_wb1_valid <= 1'b0;
            c2_wb0_pr <= 0; c2_wb0_pc <= 0; c2_wb0_oc <= 0;
            c2_wb1_pr <= 0; c2_wb1_pc <= 0; c2_wb1_oc <= 0;
            c2_wb0_sum00 <= 0; c2_wb0_sum01 <= 0;
            c2_wb0_sum10 <= 0; c2_wb0_sum11 <= 0;
            c2_wb1_q00 <= 0; c2_wb1_q01 <= 0;
            c2_wb1_q10 <= 0; c2_wb1_q11 <= 0;
            c2_commit_count <= 0;

            fc_issue_class <= 0;
            fc_issue_count <= 0;
            fc_issue_term <= 1'b0;
            fc_term0_sum <= 16'sd0;
            best_score <= -12'sd2048;
            best_idx <= 0;

            decision <= 0;
            valid_out_6 <= 1'b0;
        end else begin
            valid_out_6 <= 1'b0;

            // Conv1 writeback pipeline. The response cycle performs only the
            // fixed-point quantization into WB0. The next cycle performs the
            // max/ReLU and writes one pooled value into the seven-row ring.
            c1_wb_valid <= 1'b0;
            if (c1_wb_valid) begin
                fmap1_ring[c1_wb_oc][c1_wb_slot][c1_wb_pc] <=
                    max4_relu_a8(c1_wb_q00,c1_wb_q01,c1_wb_q10,c1_wb_q11);
                c1_commit_count <= c1_commit_count + 1'b1;
            end

            // Conv2 writeback pipeline advances every cycle.
            c2_wb0_valid <= 1'b0;
            c2_wb1_valid <= c2_wb0_valid;
            if (c2_wb0_valid) begin
                c2_wb1_pr <= c2_wb0_pr;
                c2_wb1_pc <= c2_wb0_pc;
                c2_wb1_oc <= c2_wb0_oc;
                c2_wb1_q00 <= c2_wb0_q00;
                c2_wb1_q01 <= c2_wb0_q01;
                c2_wb1_q10 <= c2_wb0_q10;
                c2_wb1_q11 <= c2_wb0_q11;
            end

            // Commit pooled Conv2 output from the isolated WB1 stage.
            if (c2_wb1_valid) begin
                fmap2[c2_wb1_oc][c2_wb1_pr][c2_wb1_pc] <=
                    max4_relu_a8(c2_wb1_q00,c2_wb1_q01,c2_wb1_q10,c2_wb1_q11);
                c2_commit_count <= c2_commit_count + 1'b1;

                // Start FC only after the 48th pooled fmap2 value is committed.
                if (c2_commit_count == 6'd47) begin
                    state <= ST_FC;
                    fc_issue_class <= 0;
                    fc_issue_count <= 0;
                    fc_issue_term <= 1'b0;
                    fc_term0_sum <= 16'sd0;
                    best_score <= -12'sd2048;
                    best_idx <= 0;
                end
            end

            // Input capture continues independently of C1/C2 scheduling.
            if (pixels_stored < 10'd784) begin
                if (!capture_primed) begin
                    capture_primed <= 1'b1;
                end else begin
                    linebuf[cap_slot][cap_col] <= data_in;
                    pixels_stored <= pixels_stored + 1'b1;

                    // Row-start preload for the current Conv1 pooled row.
                    // It fires on the exact edge that captures raw column 5 of
                    // the sixth required input row. All other 35 bytes already
                    // reside in the seven-row line buffer; the just-arriving
                    // bottom-right byte bypasses the linebuf NBA write.
                    if (!c1_window_valid &&
                        (c1_issue_pc == 4'd0) &&
                        (c1_issue_oc == 2'd0) &&
                        (cap_col == 5'd5) &&
                        (cap_row == ({c1_issue_pr,1'b0} + 5'd5))) begin
                        for (c1wr = 0; c1wr < 6; c1wr = c1wr + 1) begin
                            for (c1wc = 0; c1wc < 6; c1wc = c1wc + 1) begin
                                if ((c1wr == 5) && (c1wc == 5))
                                    c1_window[c1wr][c1wc] <= data_in;
                                else
                                    c1_window[c1wr][c1wc] <=
                                        linebuf[add_mod7(c1_base_slot,c1wr)][c1wc];
                            end
                        end
                        c1_window_valid <= 1'b1;
                        c1_new_col <= 5'd6;
                    end

                    if (cap_col == 5'd27) begin
                        cap_col <= 0;
                        if (cap_row < 5'd27)
                            cap_row <= cap_row + 1'b1;
                        cap_slot <= (cap_slot == 3'd6) ? 3'd0 : cap_slot + 1'b1;
                    end else begin
                        cap_col <= cap_col + 1'b1;
                    end
                end
            end

            // Request-side progress. Conv1 reuses the same local 6x6 window
            // for the two surviving output channels. After physical channel 1, the
            // window advances by stride 2: four columns are retained and only two entering
            // columns (12 bytes total) are fetched from linebuf.
            if (req_valid && !req_is_fc && issue_c1) begin
                c1_issue_count <= c1_issue_count + 1'b1;
                if (c1_issue_oc == 1'b0) begin
                    c1_issue_oc <= 1'b1;
                end else begin
                    c1_issue_oc <= 0;
                    if (c1_issue_pc < 11) begin
                        for (c1wr = 0; c1wr < 6; c1wr = c1wr + 1) begin
                            c1_window[c1wr][0] <= c1_window[c1wr][2];
                            c1_window[c1wr][1] <= c1_window[c1wr][3];
                            c1_window[c1wr][2] <= c1_window[c1wr][4];
                            c1_window[c1wr][3] <= c1_window[c1wr][5];
                            c1_window[c1wr][4] <=
                                linebuf[add_mod7(c1_base_slot,c1wr)][c1_new_col];
                            // With only two Conv1 channels, the horizontal
                            // window advances one cycle earlier than V24.
                            // The newest bottom-row byte is being captured on
                            // this same edge, so bypass the linebuf NBA write.
                            if ((c1wr == 5) &&
                                (cap_row == ({c1_issue_pr,1'b0} + 5'd5)) &&
                                (cap_col == (c1_new_col + 1'b1)))
                                c1_window[c1wr][5] <= data_in;
                            else
                                c1_window[c1wr][5] <=
                                    linebuf[add_mod7(c1_base_slot,c1wr)][c1_new_col + 1'b1];
                        end
                        c1_new_col <= c1_new_col + 5'd2;
                        c1_issue_pc <= c1_issue_pc + 1'b1;
                    end else begin
                        // Next pooled row starts again at raw columns 0..5.
                        // Its window is reloaded by the input-capture preload
                        // above when the new bottom row reaches column 5.
                        c1_window_valid <= 1'b0;
                        c1_new_col <= 5'd6;
                        c1_issue_pc <= 0;
                        if (c1_issue_pr < 11) begin
                            c1_issue_pr <= c1_issue_pr + 1'b1;
                            c1_base_slot <= add_mod7(c1_base_slot,2);
                        end
                    end
                end
            end

            if (req_valid && !req_is_fc && issue_c2) begin
                c2_issue_count <= c2_issue_count + 1'b1;
                if (c2_issue_ic == 1'b0) begin
                    c2_issue_ic <= 1'b1;
                end else begin
                    c2_issue_ic <= 1'b0;
                    if (c2_issue_oc < 2) begin
                        c2_issue_oc <= c2_issue_oc + 1'b1;
                    end else begin
                        c2_issue_oc <= 0;
                        if (c2_issue_pc < 3) begin
                            c2_issue_pc <= c2_issue_pc + 1'b1;
                        end else begin
                            c2_issue_pc <= 0;
                            if (c2_issue_pr < 3) begin
                                c2_issue_pr <= c2_issue_pr + 1'b1;
                                c2_base_slot <= add_mod7(c2_base_slot,2);
                            end
                        end
                    end
                end
            end

            if (req_valid && req_is_fc && state == ST_FC) begin
                fc_issue_count <= fc_issue_count + 1'b1;
                if (fc_issue_term == 1'b0) begin
                    fc_issue_term <= 1'b1;
                end else begin
                    fc_issue_term <= 1'b0;
                    if (fc_issue_class < 9)
                        fc_issue_class <= fc_issue_class + 1'b1;
                end
            end

            // Conv1 response -> WB0 quantization register. Pool/ReLU and the
            // physical ring write occur on the following cycle above.
            if (rsp_valid && !rsp_is_fc && (rsp_layer == 1'b0)) begin
                c1_wb_valid <= 1'b1;
                c1_wb_slot <= add_mod7(3'd0,rsp_pr);
                c1_wb_pc <= rsp_pc;
                c1_wb_oc <= rsp_oc;
                c1_wb_q00 <= rsp_c1q00;
                c1_wb_q01 <= rsp_c1q01;
                c1_wb_q10 <= rsp_c1q10;
                c1_wb_q11 <= rsp_c1q11;
            end

            // Conv2 response -> two-input-channel accumulation.
            // The second input-channel result is captured into WB0 instead of running
            // accumulation + quantization + pool/ReLU in one cycle.
            if (rsp_valid && !rsp_is_fc && (rsp_layer == 1'b1)) begin
                c2_rsp_count <= c2_rsp_count + 1'b1;

                if (rsp_ic == 0) begin
                    c2_acc00 <= rsp_eng20_00;
                    c2_acc01 <= rsp_eng20_01;
                    c2_acc10 <= rsp_eng20_10;
                    c2_acc11 <= rsp_eng20_11;
                end else begin
                    c2_wb0_valid <= 1'b1;
                    c2_wb0_pr <= rsp_pr[1:0];
                    c2_wb0_pc <= rsp_pc[1:0];
                    c2_wb0_oc <= rsp_oc;
                    c2_wb0_sum00 <= c2_acc00 + rsp_eng20_00;
                    c2_wb0_sum01 <= c2_acc01 + rsp_eng20_01;
                    c2_wb0_sum10 <= c2_acc10 + rsp_eng20_10;
                    c2_wb0_sum11 <= c2_acc11 + rsp_eng20_11;

                    c2_acc00 <= 0; c2_acc01 <= 0;
                    c2_acc10 <= 0; c2_acc11 <= 0;
                end
            end

            // FC SP2 is evaluated as two temporal PoT1 passes per class.
            // term0 is buffered; term1 completes the exact SP2 dot product,
            // after which the reduced-width bias/argmax datapath runs.
            if (rsp_valid && rsp_is_fc) begin
                if (rsp_fc_term == 1'b0) begin
                    fc_term0_sum <= rsp_fc_sum;
                end else begin
                    if (rsp_fc_class == 0) begin
                        best_score <= fc_score_now;
                        best_idx <= 0;
                    end else if ($signed(fc_score_now) > $signed(best_score)) begin
                        best_score <= fc_score_now;
                        best_idx <= rsp_fc_class;
                    end

                    if (rsp_fc_class == 9) begin
                        if ($signed(fc_score_now) > $signed(best_score))
                            decision <= 4'd9;
                        else
                            decision <= best_idx;
                        valid_out_6 <= 1'b1;
                        state <= ST_DONE;
                    end
                end
            end
        end
    end

endmodule
