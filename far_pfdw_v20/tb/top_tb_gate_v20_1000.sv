`timescale 1ps/1ps

// -----------------------------------------------------------------------------
// 1000-image post-synthesis netlist testbench for PFDW V20 W5.
//
// Assumes the organizer dataset layout used by the original top_tb_1000:
//   input_1000.txt contains 1000 consecutive 28x28 images (784000 bytes total)
//   expected label of image n is (n % 10), n = 0..999.
//
// IMPORTANT:
// - The prototype DUT stays in ST_DONE after each image, so this TB applies a
//   short synchronous reset between images.
// - Pixels are driven on falling clock edges so they are stable before the
//   DUT captures them on the following rising edge.
// -----------------------------------------------------------------------------
module top_tb_gate_v20_1000;
    reg clk, rst_n;
    reg [7:0] pixels [0:783999];
    reg [7:0] data_in;

    integer sample_idx;
    integer pixel_idx;
    integer expected;
    integer accuracy;
    integer fail_count;
    integer xz_count;

    wire [3:0] decision;
    wire valid_out_6;

    // Conv1
    reg signed [7:0] weight_11 [0:24];
    reg signed [7:0] weight_12 [0:24];
    reg signed [7:0] weight_13 [0:24];
    reg signed [7:0] bias_1 [0:2];

    // Conv2
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

    // FC
    reg signed [7:0] weight_fc [0:479];
    reg signed [7:0] bias_fc [0:9];

    wire [0:199]  w_11, w_12, w_13;
    wire [0:23]   b_1, b_2;
    wire [0:199]  w_211, w_212, w_213;
    wire [0:199]  w_221, w_222, w_223;
    wire [0:199]  w_231, w_232, w_233;
    wire [0:3839] w_fc;
    wire [0:79]   b_fc;

    always #5 clk = ~clk;

    chip dut (
        .clk(clk), .rst_n(rst_n), .data_in(data_in),
        .decision(decision), .valid_out_6(valid_out_6),
        .w_11(w_11), .w_12(w_12), .w_13(w_13), .b_1(b_1),
        .b_2(b_2),
        .w_211(w_211), .w_212(w_212), .w_213(w_213),
        .w_221(w_221), .w_222(w_222), .w_223(w_223),
        .w_231(w_231), .w_232(w_232), .w_233(w_233),
        .w_fc(w_fc), .b_fc(b_fc)
    );

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

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        data_in   = 8'd0;
        accuracy  = 0;
        fail_count = 0;
        xz_count   = 0;

        // Dataset: 1000 consecutive images.
        $readmemh("data/input_1000.txt", pixels);

        // Weights / biases.
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
        $display(" PFDW V20 W5 1000-image functional test start");
        $display(" Dataset : data/input_1000.txt");
        $display(" Label rule : image_index %% 10");
        $display("============================================================");

        for (sample_idx = 0; sample_idx < 1000; sample_idx = sample_idx + 1) begin
            // The prototype remains in ST_DONE after an inference, so reset it.
            rst_n   = 1'b0;
            data_in = 8'd0;
            repeat (2) @(posedge clk);

            // Match the organizer/Baseline input alignment. V2 intentionally
            // discards the first active clock (capture_primed), so provide one
            // dummy cycle before pixel 0.
            @(negedge clk);
            rst_n   = 1'b1;
            data_in = 8'd0;
            @(posedge clk);

            // Actual image starts here.
            @(negedge clk);
            data_in = pixels[sample_idx*784];

            for (pixel_idx = 1; pixel_idx < 784; pixel_idx = pixel_idx + 1) begin
                @(negedge clk);
                data_in = pixels[sample_idx*784 + pixel_idx];
            end

            // Pixel 783 is captured on the next rising edge; then wait for result.
            @(posedge clk);
            wait (valid_out_6 === 1'b1);
            #1;

            expected = sample_idx % 10;
            if ($isunknown(decision)) begin
                xz_count = xz_count + 1;
                $display("[X/Z] image=%0d decision=%b", sample_idx, decision);
            end
            if (decision == expected[3:0]) begin
                accuracy = accuracy + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] image=%0d expected=%0d decision=%0d time=%0t ps",
                         sample_idx, expected, decision, $time);
            end

            // Progress every 100 images, plus the first image.
            if ((sample_idx == 0) || (((sample_idx+1) % 100) == 0)) begin
                $display("[PROGRESS] %0d/1000  correct=%0d  fail=%0d  time=%0t ps",
                         sample_idx+1, accuracy, fail_count, $time);
            end
        end

        $display("\n============================================================");
        $display(" PFDW V20 W5 Final Accuracy for 1000 Input Images");
        $display(" Correct : %0d / 1000", accuracy);
        $display(" Fail    : %0d / 1000", fail_count);
        $display(" X/Z     : %0d", xz_count);
        $display(" Accuracy: %0.2f %%", accuracy * 100.0 / 1000.0);
        $display("============================================================\n");
        if ((accuracy < 970) || (xz_count != 0))
            $fatal(1, "RESULT: FAIL - V20 gate accuracy or X/Z gate failed.");
        else
            $display("RESULT: PASS - V20 gate accuracy and X/Z gates passed.");
        #20 $finish;
    end

    // Safety timeout: V2 is expected to be near ~10 us total for 1000 images
    // at the 10 ps functional clock; keep generous margin.
    initial begin
        #25000000; // 25 us
        $fatal(1, "[PFDW V20 W5 1000] TIMEOUT at %0t ps", $time);
    end

endmodule
