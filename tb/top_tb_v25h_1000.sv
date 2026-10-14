`timescale 1ps/1ps
// V25-H fixed-model 1000-image accuracy/cycle test.
// +DATA_DIR=C:/cnn_verilog/data +NUM_IMAGES=1000
// Expected project checkpoint: 980/1000 = 98.00%.
// Trained weight input ports are still driven for interface compatibility, but
// V25-H embeds the searched transform-domain coefficients internally.
module top_tb_v25h_1000;
    localparam CHECK_BASELINE=0;
    reg clk=0,rst_n=0;
    reg [7:0] data_in=0;
    reg [7:0] pixels[0:783999];
    reg [7:0] labels[0:999];
    wire [3:0] decision;
    wire valid_out_6;
    wire [3:0] decision_ref;
    wire valid_ref;
    integer sample_idx,pixel_idx,cycle_no,done_cycle,correct=0;
    integer base_done_cycle,base_correct=0,decision_match=0;
    integer min_cycles=2147483647,max_cycles=0,total_cycles=0,num_images=1000;
    integer random_mode,have_labels,fd,dummy;
    reg seen=0,base_seen=0;
    reg [3:0] result,base_result;
    reg [31:0] rng=32'h2468ace1;
    string data_dir="C:/cnn_verilog/data",label_file;
    always #5 clk=~clk;
    function automatic [31:0] rand32();
        begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);rand32=rng;end
    endfunction
    task automatic require_file(input string name);
        begin fd=$fopen(name,"r");if(fd==0)$fatal(1,"Cannot open %s",name);$fclose(fd);end
    endtask
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


    chip_pfdw_fc_v25h dut(.clk(clk),.rst_n(rst_n),.data_in(data_in),
        .decision(decision),.valid_out_6(valid_out_6),
        .w_11(w_11),.w_12(w_12),.w_13(w_13),.b_1(b_1),.b_2(b_2),
        .w_211(w_211),.w_212(w_212),.w_213(w_213),
        .w_221(w_221),.w_222(w_222),.w_223(w_223),
        .w_231(w_231),.w_232(w_232),.w_233(w_233),
        .w_fc(w_fc),.b_fc(b_fc));

    assign decision_ref=4'd0;
    assign valid_ref=1'b0;

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


    // Observe after NBA, independently of stream-driving task.
    always @(posedge clk) begin
        #2;
        if(rst_n && valid_out_6) begin
            if(seen) $fatal(1,"Duplicate V25-H completion image=%0d",sample_idx);
            if($isunknown(decision) || decision>9) $fatal(1,"Invalid V25-H decision");
            seen=1; result=decision; done_cycle=cycle_no;
        end
        if(rst_n && CHECK_BASELINE && valid_ref) begin
            if(base_seen) $fatal(1,"Duplicate V21 completion image=%0d",sample_idx);
            if($isunknown(decision_ref) || decision_ref>9) $fatal(1,"Invalid V21 decision");
            base_seen=1; base_result=decision_ref; base_done_cycle=cycle_no;
        end
    end
    initial begin
        dummy=$value$plusargs("DATA_DIR=%s",data_dir);
        dummy=$value$plusargs("NUM_IMAGES=%d",num_images);
        random_mode=$test$plusargs("RANDOM");
        have_labels=$value$plusargs("LABEL_FILE=%s",label_file);
        if(num_images<1 || num_images>1000) $fatal(1,"NUM_IMAGES must be 1..1000");
        
        if(!random_mode) begin
            require_file({data_dir,"/input_1000.txt"});
            $readmemh({data_dir,"/input_1000.txt"}, pixels);
            require_file({data_dir,"/conv1_weight_1.txt"});
            $readmemh({data_dir,"/conv1_weight_1.txt"}, weight_11);
            require_file({data_dir,"/conv1_weight_2.txt"});
            $readmemh({data_dir,"/conv1_weight_2.txt"}, weight_12);
            require_file({data_dir,"/conv1_weight_3.txt"});
            $readmemh({data_dir,"/conv1_weight_3.txt"}, weight_13);
            require_file({data_dir,"/conv1_bias.txt"});
            $readmemh({data_dir,"/conv1_bias.txt"}, bias_1);
            require_file({data_dir,"/conv2_bias.txt"});
            $readmemh({data_dir,"/conv2_bias.txt"}, bias_2);
            require_file({data_dir,"/conv2_weight_11.txt"});
            $readmemh({data_dir,"/conv2_weight_11.txt"}, weight_211);
            require_file({data_dir,"/conv2_weight_12.txt"});
            $readmemh({data_dir,"/conv2_weight_12.txt"}, weight_212);
            require_file({data_dir,"/conv2_weight_13.txt"});
            $readmemh({data_dir,"/conv2_weight_13.txt"}, weight_213);
            require_file({data_dir,"/conv2_weight_21.txt"});
            $readmemh({data_dir,"/conv2_weight_21.txt"}, weight_221);
            require_file({data_dir,"/conv2_weight_22.txt"});
            $readmemh({data_dir,"/conv2_weight_22.txt"}, weight_222);
            require_file({data_dir,"/conv2_weight_23.txt"});
            $readmemh({data_dir,"/conv2_weight_23.txt"}, weight_223);
            require_file({data_dir,"/conv2_weight_31.txt"});
            $readmemh({data_dir,"/conv2_weight_31.txt"}, weight_231);
            require_file({data_dir,"/conv2_weight_32.txt"});
            $readmemh({data_dir,"/conv2_weight_32.txt"}, weight_232);
            require_file({data_dir,"/conv2_weight_33.txt"});
            $readmemh({data_dir,"/conv2_weight_33.txt"}, weight_233);
            require_file({data_dir,"/fc_weight.txt"});
            $readmemh({data_dir,"/fc_weight.txt"}, weight_fc);
            require_file({data_dir,"/fc_bias.txt"});
            $readmemh({data_dir,"/fc_bias.txt"}, bias_fc);
            if(have_labels) begin
                require_file(label_file);$readmemh(label_file,labels);
            end
            for(integer i=0;i<num_images*784;i=i+1)
                if($isunknown(pixels[i])) $fatal(1,"Missing/unknown pixel %0d",i);
            if(have_labels) for(integer i=0;i<num_images;i=i+1)
                if($isunknown(labels[i]) || labels[i]>9) $fatal(1,"Invalid label %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_11[i])) $fatal(1,"Missing weight_11 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_12[i])) $fatal(1,"Missing weight_12 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_13[i])) $fatal(1,"Missing weight_13 %0d",i);
            for(integer i=0;i<3;i=i+1) if($isunknown(bias_1[i])) $fatal(1,"Missing bias_1 %0d",i);
            for(integer i=0;i<3;i=i+1) if($isunknown(bias_2[i])) $fatal(1,"Missing bias_2 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_211[i])) $fatal(1,"Missing weight_211 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_212[i])) $fatal(1,"Missing weight_212 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_213[i])) $fatal(1,"Missing weight_213 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_221[i])) $fatal(1,"Missing weight_221 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_222[i])) $fatal(1,"Missing weight_222 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_223[i])) $fatal(1,"Missing weight_223 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_231[i])) $fatal(1,"Missing weight_231 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_232[i])) $fatal(1,"Missing weight_232 %0d",i);
            for(integer i=0;i<25;i=i+1) if($isunknown(weight_233[i])) $fatal(1,"Missing weight_233 %0d",i);
            for(integer i=0;i<480;i=i+1) if($isunknown(weight_fc[i])) $fatal(1,"Missing weight_fc %0d",i);
            for(integer i=0;i<10;i=i+1) if($isunknown(bias_fc[i])) $fatal(1,"Missing bias_fc %0d",i);
        end
        for(sample_idx=0;sample_idx<num_images;sample_idx=sample_idx+1) begin
            @(negedge clk);rst_n=0;data_in=0;
            repeat(3) @(negedge clk);
            seen=0;base_seen=0;cycle_no=0;done_cycle=0;base_done_cycle=0;
            if(random_mode) begin
                for(integer i=0;i<25;i=i+1) weight_11[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_12[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_13[i]=rand32();
                for(integer i=0;i<3;i=i+1) bias_1[i]=rand32();
                for(integer i=0;i<3;i=i+1) bias_2[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_211[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_212[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_213[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_221[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_222[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_223[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_231[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_232[i]=rand32();
                for(integer i=0;i<25;i=i+1) weight_233[i]=rand32();
                for(integer i=0;i<480;i=i+1) weight_fc[i]=rand32();
                for(integer i=0;i<10;i=i+1) bias_fc[i]=rand32();
                for(integer i=0;i<784;i=i+1)
                    case(sample_idx%4)
                        0:pixels[sample_idx*784+i]=0;
                        1:pixels[sample_idx*784+i]=255;
                        2:pixels[sample_idx*784+i]=(i%2)?255:0;
                        default:pixels[sample_idx*784+i]=rand32();
                    endcase
            end
            rst_n=1; // one explicit priming edge before pixel[0]
            @(negedge clk);
            for(pixel_idx=0;pixel_idx<784;pixel_idx=pixel_idx+1) begin
                data_in=pixels[sample_idx*784+pixel_idx];
                cycle_no=pixel_idx+1; // first captured pixel is inclusive cycle 1
                @(negedge clk);
            end
            data_in=0;
            while((!seen || (CHECK_BASELINE && !base_seen)) && cycle_no<2000) begin
                cycle_no=cycle_no+1;
                @(negedge clk);
            end
            if(!seen) $fatal(1,"V25-H image timeout %0d",sample_idx);
            if(CHECK_BASELINE && !base_seen) $fatal(1,"V21 image timeout %0d",sample_idx);
            if(CHECK_BASELINE) begin
                if(result==base_result) decision_match=decision_match+1;
                if(!random_mode && base_result==(have_labels?labels[sample_idx]:(sample_idx%10))) base_correct=base_correct+1;
                if(done_cycle!=base_done_cycle)
                    $fatal(1,"Cycle mismatch V25-H=%0d V21=%0d image=%0d",done_cycle,base_done_cycle,sample_idx);
            end
            if(!random_mode && result==(have_labels?labels[sample_idx]:(sample_idx%10))) correct=correct+1;
            if(done_cycle<min_cycles) min_cycles=done_cycle;
            if(done_cycle>max_cycles) max_cycles=done_cycle;
            total_cycles=total_cycles+done_cycle;
            if(sample_idx==0 || (sample_idx+1)%100==0)
                $display("image=%0d decision=%0d inclusive_cycles=%0d",sample_idx,result,done_cycle);
            // Check that completion is a single pulse and no extra outputs follow.
            repeat(12) @(negedge clk);
        end
        $display("V25-H RUN COMPLETE: images=%0d inclusive_cycles_min=%0d max=%0d avg=%0.3f",num_images,min_cycles,max_cycles,1.0*total_cycles/num_images);
        $display("ELAPSED CYCLES: min=%0d max=%0d avg=%0.3f",min_cycles-1,max_cycles-1,1.0*total_cycles/num_images-1);
        $display("Cycle convention: pixel[0] capture=1; elapsed edge intervals=inclusive_cycles-1.");
        if(random_mode) $display("SYNTHETIC ONLY: no dataset accuracy claim");
        else $display("ACCURACY: %0d/%0d (%0.2f%%), labels=%s",correct,num_images,100.0*correct/num_images,have_labels?"file":"index modulo 10");
        if(CHECK_BASELINE) begin
            $display("BASELINE V21 ACCURACY: %0d/%0d (%0.2f%%)",base_correct,num_images,100.0*base_correct/num_images);
            $display("V25-H/V21 DECISION MATCH: %0d/%0d (%0.2f%%)",decision_match,num_images,100.0*decision_match/num_images);
        end
        if(!random_mode && !have_labels && num_images==1000) begin
            if(correct != 980)
                $fatal(1,"V25-H checkpoint mismatch: expected 980/1000, got %0d/1000",correct);
            else
                $display("V25-H CHECKPOINT PASS: 980/1000 (98.00%%)");
        end
        $finish;
    end
    initial begin #25000000;$fatal(1,"GLOBAL TIMEOUT");end
endmodule
