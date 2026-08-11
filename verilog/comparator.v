
/*------------------------------------------------------------------------
 *
 *  Copyright (c) 2021 by Bo Young Kang, All rights reserved.
 *
 *  File name  : comparator.v
 *  Written by : Kang, Bo Young
 *  Written on : Oct 13, 2021
 *  Version    : 21.2
 *  Design     : Final Comparator for decision
 *
 *------------------------------------------------------------------------*/

/*------------------------------------------------------------------------
 *
 *  Modified: Buffer 비교 제거 및 max value만 기억하게 최적화
 *
 *------------------------------------------------------------------------*/

/*-------------------------------------------------------------------
 *  Module: comparator
 *------------------------------------------------------------------*/

module comparator (
  input clk,
  input rst_n,
  input valid_in,
  input signed [11:0] data_in,
  output reg [3:0] decision,
  output reg valid_out
);

// reg signed [11:0] buffer [0:9];
// reg signed [11:0] max;
// reg signed [11:0] cmp1_0, cmp1_1, cmp1_2, cmp1_3, cmp1_4,
//                   cmp2_0, cmp2_1, cmp2_2,
//                   cmp3_0, cmp3_1;
// reg [3:0] buf_idx;
// reg [11:0] delay_cnt;
// reg state;
 reg signed [11:0] max_value;
 reg [3:0] max_idx;
 reg [3:0] input_idx;

always @(posedge clk) begin
  if(~rst_n) begin
    max_value <= 12'sd0;
    max_idx <= 4'd0;
    input_idx <= 4'd0;
    decision <= 4'd0;
    valid_out <= 1'b0;
  end
  else begin
    valid_out <= 1'b0;
    if (valid_in) begin
      /*
      첫번째 FC output
      max value 초기화
      */
      if (input_idx == 4'd0) begin
        max_value <= data_in;
        max_idx <= 4'd0;
        input_idx <= 4'd1;
      end
      /*
      마지막 FC output (9번째 cls)
      */
      else if (input_idx == 4'd9) begin
        if (data_in > max_value) begin
          decision <= 4'd9;
        end
        else begin
          decision <= max_idx;
        end
        valid_out <= 1'b1;
        
        // 초기 상태로 복귀
        input_idx <= 4'd0;
        max_idx <= 4'd0;
        max_value <= 12'sd0;
      end
      else begin
        if (data_in > max_value) begin
          max_value <= data_in;
          max_idx <= input_idx;
        end
        input_idx <= input_idx + 1'b1;
      end
    end
  end
end
endmodule