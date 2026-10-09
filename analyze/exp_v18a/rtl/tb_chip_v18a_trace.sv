`timescale 1ps/1ps

// Read-only V18A top trace. Drive at negedge; record arithmetic before NBA.
module tb_chip_v18a_trace;
    reg clk, rst_n;
    reg [7:0] pixels [0:783999];
    reg [7:0] data_in;

    integer sample_idx;
    integer pixel_idx;
    integer expected;
    integer accuracy;
    integer fail_count;

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

    always #5000 clk = ~clk;

    chip_pfdw_fc_v18a dut (
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


    string data_dir, trace_csv;
    integer trace_fd, image_count, cycle_count=0, first_pixel_edge, elapsed_cycles, wait_edges;
    function automatic signed [11:0] pooled(input signed [11:0] a,b,c,d);
        reg signed [11:0] m;
        begin
            m=a;if(b>m)m=b;if(c>m)m=c;if(d>m)m=d;
            pooled=(m>0)?m:12'sd0;
        end
    endfunction
    // All these signals are consumed by the DUT on this edge. Recording before
    // NBA keeps their valid flags and tags aligned with the old register payload.
    always @(posedge clk) begin
        cycle_count=cycle_count+1;
        if(rst_n && trace_fd) begin
            if(dut.rsp_valid && !dut.rsp_is_fc) begin
                if(!dut.rsp_layer) begin
                    $fdisplay(trace_fd,"C1RAW,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.rsp_oc,2*dut.rsp_pr,2*dut.rsp_pc,$signed(dut.rsp_y00));
                    $fdisplay(trace_fd,"C1RAW,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.rsp_oc,2*dut.rsp_pr,2*dut.rsp_pc+1,$signed(dut.rsp_y01));
                    $fdisplay(trace_fd,"C1RAW,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.rsp_oc,2*dut.rsp_pr+1,2*dut.rsp_pc,$signed(dut.rsp_y10));
                    $fdisplay(trace_fd,"C1RAW,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.rsp_oc,2*dut.rsp_pr+1,2*dut.rsp_pc+1,$signed(dut.rsp_y11));
                end else begin
                    $fdisplay(trace_fd,"C2RAW,%0d,%0d,%0d,%0d,%0d,%0d",sample_idx,dut.rsp_oc,dut.rsp_ic,2*dut.rsp_pr,2*dut.rsp_pc,$signed(dut.rsp_y00));
                    $fdisplay(trace_fd,"C2RAW,%0d,%0d,%0d,%0d,%0d,%0d",sample_idx,dut.rsp_oc,dut.rsp_ic,2*dut.rsp_pr,2*dut.rsp_pc+1,$signed(dut.rsp_y01));
                    $fdisplay(trace_fd,"C2RAW,%0d,%0d,%0d,%0d,%0d,%0d",sample_idx,dut.rsp_oc,dut.rsp_ic,2*dut.rsp_pr+1,2*dut.rsp_pc,$signed(dut.rsp_y10));
                    $fdisplay(trace_fd,"C2RAW,%0d,%0d,%0d,%0d,%0d,%0d",sample_idx,dut.rsp_oc,dut.rsp_ic,2*dut.rsp_pr+1,2*dut.rsp_pc+1,$signed(dut.rsp_y11));
                end
            end
            if(dut.c1_wb_valid)
                $fdisplay(trace_fd,"POOL1,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.c1_wb_oc,dut.c1_commit_count/36,dut.c1_wb_pc,
                          pooled(dut.c1_wb_q00,dut.c1_wb_q01,dut.c1_wb_q10,dut.c1_wb_q11));
            if(dut.c2_wb1_valid)
                $fdisplay(trace_fd,"POOL2,%0d,%0d,%0d,%0d,0,%0d",sample_idx,dut.c2_wb1_oc,dut.c2_wb1_pr,dut.c2_wb1_pc,
                          pooled(dut.c2_wb1_q00,dut.c2_wb1_q01,dut.c2_wb1_q10,dut.c2_wb1_q11));
            if(dut.rsp_valid && dut.rsp_is_fc)
                $fdisplay(trace_fd,"LOGIT,%0d,%0d,0,0,0,%0d",sample_idx,dut.rsp_fc_class,$signed(dut.fc_score_now));
        end
    end
    initial begin
        clk=0;rst_n=0;data_in=0;accuracy=0;sample_idx=0;trace_fd=0;
        if(!$value$plusargs("DATA_DIR=%s",data_dir)) $fatal(1,"+DATA_DIR is required");
        if(!$value$plusargs("TRACE_CSV=%s",trace_csv)) $fatal(1,"+TRACE_CSV is required");
        if(!$value$plusargs("IMAGES=%d",image_count)) image_count=1000;
        if(image_count<1 || image_count>1000) $fatal(1,"IMAGES must be 1..1000");
        trace_fd=$fopen(trace_csv,"w");if(!trace_fd)$fatal(1,"cannot open trace output");
        $fdisplay(trace_fd,"kind,image,a,b,c,d,value");
        $readmemh({data_dir,"/input_1000.txt"}, pixels);
        $readmemh({data_dir,"/conv1_weight_1.txt"}, weight_11);
        $readmemh({data_dir,"/conv1_weight_2.txt"}, weight_12);
        $readmemh({data_dir,"/conv1_weight_3.txt"}, weight_13);
        $readmemh({data_dir,"/conv1_bias.txt"}, bias_1);
        $readmemh({data_dir,"/conv2_bias.txt"}, bias_2);
        $readmemh({data_dir,"/conv2_weight_11.txt"}, weight_211);
        $readmemh({data_dir,"/conv2_weight_12.txt"}, weight_212);
        $readmemh({data_dir,"/conv2_weight_13.txt"}, weight_213);
        $readmemh({data_dir,"/conv2_weight_21.txt"}, weight_221);
        $readmemh({data_dir,"/conv2_weight_22.txt"}, weight_222);
        $readmemh({data_dir,"/conv2_weight_23.txt"}, weight_223);
        $readmemh({data_dir,"/conv2_weight_31.txt"}, weight_231);
        $readmemh({data_dir,"/conv2_weight_32.txt"}, weight_232);
        $readmemh({data_dir,"/conv2_weight_33.txt"}, weight_233);
        $readmemh({data_dir,"/fc_weight.txt"}, weight_fc);
        $readmemh({data_dir,"/fc_bias.txt"}, bias_fc);
        for(sample_idx=0;sample_idx<image_count;sample_idx=sample_idx+1) begin
            @(negedge clk);rst_n=0;data_in=0;
            repeat(2) @(negedge clk);
            rst_n=1;data_in=0; // one dummy capture edge; capture_primed then becomes true
            @(negedge clk);data_in=pixels[sample_idx*784];
            first_pixel_edge=cycle_count+1;
            for(pixel_idx=1;pixel_idx<784;pixel_idx=pixel_idx+1) begin
                @(negedge clk);data_in=pixels[sample_idx*784+pixel_idx];
            end
            @(posedge clk);#1;
            wait_edges=0;
            while(valid_out_6!==1'b1 && wait_edges<5000) begin
                @(posedge clk);#1;wait_edges=wait_edges+1;
            end
            if(valid_out_6!==1'b1)$fatal(1,"image timeout %0d",sample_idx);
            if((^decision)===1'bx)$fatal(1,"unknown decision %0d",sample_idx);
            expected=sample_idx%10;
            if(decision==expected)accuracy=accuracy+1;
            elapsed_cycles=cycle_count-first_pixel_edge+1;
            $fdisplay(trace_fd,"DECISION,%0d,0,0,0,0,%0d",sample_idx,decision);
            $fdisplay(trace_fd,"CYCLES,%0d,0,0,0,0,%0d",sample_idx,elapsed_cycles);
            if(sample_idx%100==0)$display("TRACE image=%0d cycles=%0d",sample_idx,elapsed_cycles);
        end
        $display("TRACE_DONE correct=%0d/%0d",accuracy,image_count);
        $fclose(trace_fd);trace_fd=0;$finish;
    end
    initial begin #100000000000;$fatal(1,"global trace timeout");end
endmodule
