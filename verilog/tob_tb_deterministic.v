`timescale 1ps/1ps

module top_tb_deterministic;

  parameter DATA_ROOT =
    "C:/Users/surt1_xl6lr7u/Downloads/idec/Reference code/Reference code/Reference code/proposed/data";

  parameter RESULT_FILE =
    "C:/Users/surt1_xl6lr7u/Downloads/idec/Reference code/Reference code/Reference code/proposed/analyze/outputs/rtl_predictions.csv";

  reg clk;
  reg rst_n;
  reg [7:0] data_in;

  reg [7:0] pixels [0:783999];

  wire [3:0] decision;
  wire valid_out_6;

  // ============================================================
  // Conv1 parameters
  // ============================================================

  reg signed [7:0] weight_11 [0:24];
  reg signed [7:0] weight_12 [0:24];
  reg signed [7:0] weight_13 [0:24];

  reg signed [7:0] bias_1 [0:2];

  // ============================================================
  // Conv2 parameters
  // ============================================================

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

  // ============================================================
  // FC parameters
  // ============================================================

  reg signed [7:0] weight_fc [0:479];
  reg signed [7:0] bias_fc [0:9];

  // ============================================================
  // Packed buses to DUT
  // ============================================================

  wire [0:199] w_11;
  wire [0:199] w_12;
  wire [0:199] w_13;

  wire [0:23] b_1;
  wire [0:23] b_2;

  wire [0:199] w_211;
  wire [0:199] w_212;
  wire [0:199] w_213;

  wire [0:199] w_221;
  wire [0:199] w_222;
  wire [0:199] w_223;

  wire [0:199] w_231;
  wire [0:199] w_232;
  wire [0:199] w_233;

  wire [0:3839] w_fc;
  wire [0:79] b_fc;

  integer result_fd;
  integer image_id;
  integer total_correct;
  integer cycle_count;

  // ============================================================
  // Clock
  // ============================================================

  initial begin
    clk = 1'b0;
  end

  always #5 clk = ~clk;


  // ============================================================
  // Per-inference cycle counter
  // ============================================================

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end
    else begin
      cycle_count <= cycle_count + 1;
    end
  end


  // ============================================================
  // Parameter packing
  // ============================================================

  genvar g;

  generate

    for (g = 0; g < 25; g = g + 1) begin : GEN_CONV_WEIGHT_PACK

      assign w_11[(8*g)+:8] = weight_11[g];
      assign w_12[(8*g)+:8] = weight_12[g];
      assign w_13[(8*g)+:8] = weight_13[g];

      assign w_211[(8*g)+:8] = weight_211[g];
      assign w_212[(8*g)+:8] = weight_212[g];
      assign w_213[(8*g)+:8] = weight_213[g];

      assign w_221[(8*g)+:8] = weight_221[g];
      assign w_222[(8*g)+:8] = weight_222[g];
      assign w_223[(8*g)+:8] = weight_223[g];

      assign w_231[(8*g)+:8] = weight_231[g];
      assign w_232[(8*g)+:8] = weight_232[g];
      assign w_233[(8*g)+:8] = weight_233[g];

    end

    for (g = 0; g < 3; g = g + 1) begin : GEN_CONV_BIAS_PACK

      assign b_1[(8*g)+:8] = bias_1[g];
      assign b_2[(8*g)+:8] = bias_2[g];

    end

    for (g = 0; g < 480; g = g + 1) begin : GEN_FC_WEIGHT_PACK

      assign w_fc[(8*g)+:8] = weight_fc[g];

    end

    for (g = 0; g < 10; g = g + 1) begin : GEN_FC_BIAS_PACK

      assign b_fc[(8*g)+:8] = bias_fc[g];

    end

  endgenerate


  // ============================================================
  // DUT
  // ============================================================

  chip chip1 (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(data_in),
    .decision(decision),
    .valid_out_6(valid_out_6),

    .w_11(w_11),
    .w_12(w_12),
    .w_13(w_13),
    .b_1(b_1),

    .b_2(b_2),

    .w_211(w_211),
    .w_212(w_212),
    .w_213(w_213),

    .w_221(w_221),
    .w_222(w_222),
    .w_223(w_223),

    .w_231(w_231),
    .w_232(w_232),
    .w_233(w_233),

    .w_fc(w_fc),
    .b_fc(b_fc)
  );


  // ============================================================
  // Run exactly one image
  // ============================================================

  task run_one_image;

    input integer current_image;

    integer pixel_idx;
    integer base_idx;
    integer expected;

    begin

      base_idx = current_image * 784;
      expected = current_image % 10;

      // --------------------------------------------------------
      // Reset between images
      // --------------------------------------------------------

      rst_n = 1'b0;
      data_in = 8'd0;

      repeat (2) begin
        @(negedge clk);
      end

      // --------------------------------------------------------
      // Release reset and present pixel 0 before next posedge
      // --------------------------------------------------------

      rst_n = 1'b1;
      data_in = pixels[base_idx];

      // pixel 0 is now stable before the next rising edge.
      // Feed pixels 1 ... 783 on following falling edges.

      for (
        pixel_idx = 1;
        pixel_idx < 784;
        pixel_idx = pixel_idx + 1
      ) begin

        @(negedge clk);

        data_in = pixels[
          base_idx + pixel_idx
        ];

      end

      // Ensure pixel 783 is sampled at the next rising edge.
      @(negedge clk);

      // No further image data should pollute the current inference.
      data_in = 8'd0;

      // --------------------------------------------------------
      // Wait for final decision
      // --------------------------------------------------------

      wait(valid_out_6 === 1'b1);

      // Allow NBA updates at the decision edge to settle.
      #1;

      $fwrite(
        result_fd,
        "%0d,%0d,%0d,%0d\n",
        current_image,
        expected,
        decision,
        cycle_count
      );

      if (decision == expected) begin
        total_correct = total_correct + 1;
      end

      if (
        ((current_image + 1) % 100) == 0
      ) begin

        $display(
          "Processed %0d / 1000, current correct = %0d",
          current_image + 1,
          total_correct
        );

      end

    end

  endtask


  // ============================================================
  // Main test
  // ============================================================

  initial begin

    rst_n = 1'b0;
    data_in = 8'd0;

    cycle_count = 0;
    total_correct = 0;

    // ----------------------------------------------------------
    // Input images
    // ----------------------------------------------------------

    $readmemh(
      {DATA_ROOT, "/input_1000.txt"},
      pixels
    );

    // ----------------------------------------------------------
    // Conv1
    // ----------------------------------------------------------

    $readmemh(
      {DATA_ROOT, "/conv1_weight_1.txt"},
      weight_11
    );

    $readmemh(
      {DATA_ROOT, "/conv1_weight_2.txt"},
      weight_12
    );

    $readmemh(
      {DATA_ROOT, "/conv1_weight_3.txt"},
      weight_13
    );

    $readmemh(
      {DATA_ROOT, "/conv1_bias.txt"},
      bias_1
    );

    // ----------------------------------------------------------
    // Conv2
    // ----------------------------------------------------------

    $readmemh(
      {DATA_ROOT, "/conv2_bias.txt"},
      bias_2
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_11.txt"},
      weight_211
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_12.txt"},
      weight_212
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_13.txt"},
      weight_213
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_21.txt"},
      weight_221
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_22.txt"},
      weight_222
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_23.txt"},
      weight_223
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_31.txt"},
      weight_231
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_32.txt"},
      weight_232
    );

    $readmemh(
      {DATA_ROOT, "/conv2_weight_33.txt"},
      weight_233
    );

    // ----------------------------------------------------------
    // FC
    // ----------------------------------------------------------

    $readmemh(
      {DATA_ROOT, "/fc_weight.txt"},
      weight_fc
    );

    $readmemh(
      {DATA_ROOT, "/fc_bias.txt"},
      bias_fc
    );

    // ----------------------------------------------------------
    // Output CSV
    // ----------------------------------------------------------

    result_fd = $fopen(
      RESULT_FILE,
      "w"
    );

    if (result_fd == 0) begin

      $display(
        "ERROR: Cannot open result file: %s",
        RESULT_FILE
      );

      $finish;

    end

    $fwrite(
      result_fd,
      "image_index,expected,predicted,cycles\n"
    );

    // ----------------------------------------------------------
    // Deterministic image 0 -> 999
    // ----------------------------------------------------------

    for (
      image_id = 0;
      image_id < 1000;
      image_id = image_id + 1
    ) begin

      run_one_image(
        image_id
      );

    end

    rst_n = 1'b0;
    data_in = 8'd0;

    $fclose(
      result_fd
    );

    $display("");
    $display(
      "========================================"
    );

    $display(
      "Deterministic RTL correct = %0d / 1000",
      total_correct
    );

    $display(
      "Deterministic RTL accuracy = %0d %%",
      total_correct / 10
    );

    $display(
      "RTL predictions saved to:"
    );

    $display(
      "%s",
      RESULT_FILE
    );

    $display(
      "========================================"
    );

    $finish;

  end

endmodule