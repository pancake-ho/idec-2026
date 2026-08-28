`timescale 1ps/1ps

// ============================================================================
// V18A vs V19 FAR direct-decision comparison for 1000 images.
//
// - Feeds the EXACT SAME image stream to both DUTs.
// - Uses images 0..999 exactly once.
// - Latches each DUT's decision when its own valid_out_6 asserts.
// - Reports:
//     1) Baseline accuracy
//     2) PFDW+FC accuracy
//     3) Baseline-vs-PFDW decision match count
//
// Required design sources:
//   Baseline: chip.v, conv1.v, conv2.v, maxpool_relu.v, fc.v, comparator.v
//   PFDW   : chip_pfdw_fc_proto.sv, pfdw_shared_engine.sv
// ============================================================================

module top_tb_far_vs_v18a_1000;

    reg clk, rst_n;
    reg [7:0] pixels [0:783999];
    reg [7:0] data_in;

    integer sample_idx;
    integer pixel_idx;
    integer expected;

    integer baseline_correct;
    integer pfdw_correct;
    integer match_count;
    integer mismatch_count;

    // Baseline outputs
    wire [3:0] decision_base;
    wire       valid_base;

    // PFDW outputs
    wire [3:0] decision_pfdw;
    wire       valid_pfdw;

    // Latched results, because the two DUTs can finish at different times
    reg        base_seen;
    reg        pfdw_seen;
    reg [3:0]  base_dec_latched;
    reg [3:0]  pfdw_dec_latched;

    // ------------------------------------------------------------------------
    // Weights / biases
    // ------------------------------------------------------------------------
    reg signed [7:0] weight_11 [0:24];
    reg signed [7:0] weight_12 [0:24];
    reg signed [7:0] weight_13 [0:24];
    reg signed [7:0] bias_1 [0:2];

    reg signed [7:0] bias_2 [0:2];
    reg signed [7:0] weight_211 [0:24];
    reg signed [7:0] weight_212 [0:24];
    reg signed [7:0] weight_213 [0:24];
    reg signed [7:0] weight_221 [0:24];
    reg signed [7:0] weight_222 [0:24];
    reg signed [7:0] weight_223 [0:24];
    reg signed [7:0] weight_231 [0:24];
    reg signed [7:0] weight_232 [0:24];
    reg signed [7:0] weight_233 [0:24];

    reg signed [7:0] weight_fc [0:479];
    reg signed [7:0] bias_fc [0:9];

    wire [0:199]  w_11, w_12, w_13;
    wire [0:23]   b_1, b_2;
    wire [0:199]  w_211, w_212, w_213;
    wire [0:199]  w_221, w_222, w_223;
    wire [0:199]  w_231, w_232, w_233;
    wire [0:3839] w_fc;
    wire [0:79]   b_fc;

    // 10 ps clock period
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Frozen V18A reference DUT
    // ------------------------------------------------------------------------
    chip_pfdw_fc_v18a dut_baseline (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .decision(decision_base),
        .valid_out_6(valid_base),

        .w_11(w_11), .w_12(w_12), .w_13(w_13), .b_1(b_1),
        .b_2(b_2),

        .w_211(w_211), .w_212(w_212), .w_213(w_213),
        .w_221(w_221), .w_222(w_222), .w_223(w_223),
        .w_231(w_231), .w_232(w_232), .w_233(w_233),

        .w_fc(w_fc), .b_fc(b_fc)
    );

    // ------------------------------------------------------------------------
    // PFDW + shared-FC DUT
    // ------------------------------------------------------------------------
    chip_pfdw_fc_v19_far dut_pfdw (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .decision(decision_pfdw),
        .valid_out_6(valid_pfdw),

        .w_11(w_11), .w_12(w_12), .w_13(w_13), .b_1(b_1),
        .b_2(b_2),

        .w_211(w_211), .w_212(w_212), .w_213(w_213),
        .w_221(w_221), .w_222(w_222), .w_223(w_223),
        .w_231(w_231), .w_232(w_232), .w_233(w_233),

        .w_fc(w_fc), .b_fc(b_fc)
    );

    // ------------------------------------------------------------------------
    // Pack weight arrays into flat DUT buses
    // ------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi=0; gi<25; gi=gi+1) begin: PACK_CONV
            assign w_11 [(8*gi)+:8] = weight_11[gi];
            assign w_12 [(8*gi)+:8] = weight_12[gi];
            assign w_13 [(8*gi)+:8] = weight_13[gi];

            assign w_211[(8*gi)+:8] = weight_211[gi];
            assign w_212[(8*gi)+:8] = weight_212[gi];
            assign w_213[(8*gi)+:8] = weight_213[gi];

            assign w_221[(8*gi)+:8] = weight_221[gi];
            assign w_222[(8*gi)+:8] = weight_222[gi];
            assign w_223[(8*gi)+:8] = weight_223[gi];

            assign w_231[(8*gi)+:8] = weight_231[gi];
            assign w_232[(8*gi)+:8] = weight_232[gi];
            assign w_233[(8*gi)+:8] = weight_233[gi];
        end

        for (gi=0; gi<3; gi=gi+1) begin: PACK_BIAS_CONV
            assign b_1[(8*gi)+:8] = bias_1[gi];
            assign b_2[(8*gi)+:8] = bias_2[gi];
        end

        for (gi=0; gi<480; gi=gi+1) begin: PACK_FC
            assign w_fc[(8*gi)+:8] = weight_fc[gi];
        end

        for (gi=0; gi<10; gi=gi+1) begin: PACK_BIAS_FC
            assign b_fc[(8*gi)+:8] = bias_fc[gi];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Latch decisions independently because finish times are different.
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            base_seen        <= 1'b0;
            pfdw_seen        <= 1'b0;
            base_dec_latched <= 4'd0;
            pfdw_dec_latched <= 4'd0;
        end else begin
            if (valid_base && !base_seen) begin
                base_seen        <= 1'b1;
                base_dec_latched <= decision_base;
            end

            if (valid_pfdw && !pfdw_seen) begin
                pfdw_seen        <= 1'b1;
                pfdw_dec_latched <= decision_pfdw;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------------------
    initial begin
        clk              = 1'b0;
        rst_n            = 1'b0;
        data_in          = 8'd0;

        baseline_correct = 0;
        pfdw_correct     = 0;
        match_count      = 0;
        mismatch_count   = 0;

        // Dataset
        $readmemh("data/input_1000.txt", pixels);

        // Weights / biases
        $readmemh("data/conv1_weight_1.txt", weight_11);
        $readmemh("data/conv1_weight_2.txt", weight_12);
        $readmemh("data/conv1_weight_3.txt", weight_13);
        $readmemh("data/conv1_bias.txt", bias_1);

        $readmemh("data/conv2_bias.txt", bias_2);
        $readmemh("data/conv2_weight_11.txt", weight_211);
        $readmemh("data/conv2_weight_12.txt", weight_212);
        $readmemh("data/conv2_weight_13.txt", weight_213);
        $readmemh("data/conv2_weight_21.txt", weight_221);
        $readmemh("data/conv2_weight_22.txt", weight_222);
        $readmemh("data/conv2_weight_23.txt", weight_223);
        $readmemh("data/conv2_weight_31.txt", weight_231);
        $readmemh("data/conv2_weight_32.txt", weight_232);
        $readmemh("data/conv2_weight_33.txt", weight_233);

        $readmemh("data/fc_weight.txt", weight_fc);
        $readmemh("data/fc_bias.txt", bias_fc);

        $display("============================================================");
        $display(" PFDW V18A vs V19 FAR: 1000-image comparison");
        $display(" Images      : 0..999, each exactly once");
        $display(" Label rule  : image_index %% 10");
        $display("============================================================");

        for (sample_idx = 0; sample_idx < 1000; sample_idx = sample_idx + 1) begin

            // Reset BOTH designs between images.
            rst_n   = 1'b0;
            data_in = 8'd0;
            repeat (3) @(posedge clk);

            // Deassert reset with dummy data first. Both DUTs intentionally
            // consume one priming cycle:
            //   - Baseline: conv1_buf has buf_idx=-1, so this cycle is discarded.
            //   - PFDW sync version: capture_primed discards this cycle.
            @(negedge clk);
            rst_n   = 1'b1;
            data_in = 8'd0;
            @(posedge clk);

            // Now present the actual image. Both DUTs map pixels[0] to their
            // logical first pixel position.
            @(negedge clk);
            data_in = pixels[sample_idx*784];

            for (pixel_idx = 1; pixel_idx < 784; pixel_idx = pixel_idx + 1) begin
                @(negedge clk);
                data_in = pixels[sample_idx*784 + pixel_idx];
            end

            // Last pixel is captured on next posedge.
            @(posedge clk);

            // Wait until BOTH independently latched their outputs.
            wait (base_seen && pfdw_seen);
            #1;

            expected = sample_idx % 10;

            if (base_dec_latched == expected[3:0])
                baseline_correct = baseline_correct + 1;

            if (pfdw_dec_latched == expected[3:0])
                pfdw_correct = pfdw_correct + 1;

            if (base_dec_latched == pfdw_dec_latched) begin
                match_count = match_count + 1;
            end else begin
                mismatch_count = mismatch_count + 1;
                $display("[DECISION MISMATCH] image=%0d expected=%0d baseline=%0d pfdw=%0d time=%0t ps",
                         sample_idx, expected, base_dec_latched, pfdw_dec_latched, $time);
            end

            if ((sample_idx == 0) || (((sample_idx+1) % 100) == 0)) begin
                $display("[PROGRESS] %0d/1000  base_acc=%0d  pfdw_acc=%0d  match=%0d mismatch=%0d",
                         sample_idx+1, baseline_correct, pfdw_correct,
                         match_count, mismatch_count);
            end
        end

        $display("");
        $display("============================================================");
        $display(" FINAL COMPARISON");
        $display(" V18A correct    : %0d / 1000  (%0.2f %%)",
                 baseline_correct, baseline_correct * 100.0 / 1000.0);
        $display(" PFDW correct     : %0d / 1000  (%0.2f %%)",
                 pfdw_correct, pfdw_correct * 100.0 / 1000.0);
        $display(" Decision match   : %0d / 1000  (%0.2f %%)",
                 match_count, match_count * 100.0 / 1000.0);
        $display(" Decision mismatch: %0d / 1000", mismatch_count);
        $display("============================================================");

        if (match_count == 1000)
            $display(" RESULT: PASS - FAR is decision-identical to V18A for all 1000 images.");
        else
            $display(" RESULT: CHECK - Some Baseline/PFDW classification decisions differ.");

        #20 $finish;
    end

    // Generous timeout. Both designs run in parallel.
    initial begin
        #90000000; // 90 us
        $display("[COMPARE 1000] TIMEOUT at %0t ps", $time);
        $finish;
    end

endmodule
