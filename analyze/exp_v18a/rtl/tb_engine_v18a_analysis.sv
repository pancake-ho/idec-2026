`timescale 1ps/1ps
// RTL-only engine contract test: modes, tag, outputs, bubbles, fixed latency.
// Run with +VECTORS=/absolute/path/engine_cases.txt . No source DUT changes.
module tb_engine_v18a_analysis;
    logic clk=0, rst_n=0, req_valid=0, req_is_fc=0;
    logic [15:0] req_tag=0;
    logic signed [11:0] conv_tile[0:5][0:5];
    logic signed [7:0] conv_kernel[0:4][0:4];
    logic signed [11:0] fc_a[0:47];
    logic signed [7:0] fc_b[0:47];
    wire rsp_valid,rsp_is_fc;
    wire [15:0] rsp_tag;
    wire signed [31:0] y00,y01,y10,y11;
    wire signed [39:0] fc_sum;
    integer fd,ncases,idx,mode,rc,k,r,c;
    integer sent=0,received=0,edge_no=0;
    integer accepted_edge[0:59999];
    bit accepted[0:59999],completed[0:59999],expected_mode[0:59999];
    longint signed exp_y[0:59999][0:3],exp_fc[0:59999];
    longint signed aa[0:47],bb[0:47],temp;
    string vectors;
    bit driving_done=0;
    always #5000 clk=~clk;
    pfdw_pipe49_booth_engine_v18a dut(
        .clk(clk),.rst_n(rst_n),.req_valid(req_valid),.req_is_fc(req_is_fc),.req_tag(req_tag),
        .conv_tile(conv_tile),.conv_kernel(conv_kernel),.fc_a(fc_a),.fc_b(fc_b),
        .rsp_valid(rsp_valid),.rsp_is_fc(rsp_is_fc),.rsp_tag(rsp_tag),
        .conv_y00(y00),.conv_y01(y01),.conv_y10(y10),.conv_y11(y11),.fc_sum(fc_sum));

    always @(posedge clk) begin
        edge_no=edge_no+1;
        if(rst_n && req_valid) begin
            if(accepted[req_tag]) $fatal(1,"duplicate accepted tag %0d",req_tag);
            accepted[req_tag]=1;
            accepted_edge[req_tag]=edge_no;
            sent=sent+1;
        end
        #1; // Observe NBA response registers, not previous-cycle values.
        if(rst_n && rsp_valid) begin
            if(!accepted[rsp_tag] || completed[rsp_tag]) $fatal(1,"unexpected response tag");
            if(edge_no-accepted_edge[rsp_tag]!=6) $fatal(1,"valid latency mismatch tag=%0d",rsp_tag);
            if(rsp_is_fc !== expected_mode[rsp_tag]) $fatal(1,"mode mismatch");
            if(rsp_is_fc) begin
                if($signed(fc_sum)!==exp_fc[rsp_tag]) $fatal(1,"FC mismatch tag=%0d",rsp_tag);
            end else begin
                if($signed(y00)!==exp_y[rsp_tag][0] || $signed(y01)!==exp_y[rsp_tag][1] ||
                   $signed(y10)!==exp_y[rsp_tag][2] || $signed(y11)!==exp_y[rsp_tag][3])
                    $fatal(1,"Conv mismatch tag=%0d",rsp_tag);
            end
            completed[rsp_tag]=1;
            received=received+1;
        end
    end

    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"+VECTORS is required");
        fd=$fopen(vectors,"r");
        if(!fd) $fatal(1,"cannot open vectors");
        rc=$fscanf(fd,"%d",ncases);
        if(rc!=1 || ncases<4 || ncases>60000) $fatal(1,"bad vector count");
        for(k=0;k<60000;k=k+1) begin accepted[k]=0;completed[k]=0;end
        for(r=0;r<6;r=r+1) for(c=0;c<6;c=c+1) conv_tile[r][c]=0;
        for(r=0;r<5;r=r+1) for(c=0;c<5;c=c+1) conv_kernel[r][c]=0;
        for(k=0;k<48;k=k+1) begin fc_a[k]=0;fc_b[k]=0;end
        repeat(3) @(negedge clk);
        rst_n=1;
        for(idx=0;idx<ncases;idx=idx+1) begin
            @(negedge clk);
            // A bubble must propagate through valid without duplicating payload.
            if(idx%11==0) begin req_valid=0; @(negedge clk);end
            rc=$fscanf(fd,"%d %d",k,mode);
            if(rc!=2 || k!=idx || (mode!=0 && mode!=1)) $fatal(1,"bad vector header");
            for(k=0;k<48;k=k+1) begin rc=$fscanf(fd,"%d",aa[k]);if(rc!=1)$fatal(1,"bad A");end
            for(k=0;k<48;k=k+1) begin rc=$fscanf(fd,"%d",bb[k]);if(rc!=1)$fatal(1,"bad B");end
            for(k=0;k<4;k=k+1) begin rc=$fscanf(fd,"%d",exp_y[idx][k]);if(rc!=1)$fatal(1,"bad Y");end
            rc=$fscanf(fd,"%d",exp_fc[idx]);if(rc!=1)$fatal(1,"bad FC expected");
            expected_mode[idx]=mode;
            req_valid=1;req_is_fc=mode;req_tag=idx;
            for(r=0;r<6;r=r+1) for(c=0;c<6;c=c+1) conv_tile[r][c]=aa[r*6+c];
            for(r=0;r<5;r=r+1) for(c=0;c<5;c=c+1) conv_kernel[r][c]=bb[r*5+c];
            for(k=0;k<48;k=k+1) begin fc_a[k]=aa[k];fc_b[k]=bb[k];end
        end
        @(negedge clk);req_valid=0;driving_done=1;
        repeat(10) @(negedge clk);
        if(sent!=ncases || received!=ncases) $fatal(1,"lost transaction sent=%0d received=%0d",sent,received);
        $display("ENGINE_CONTRACT_PASS cases=%0d latency_edge_offset=6 stages=7",ncases);
        $fclose(fd);$finish;
    end
    initial begin
        #100000000000; $fatal(1,"engine timeout");
    end
endmodule
