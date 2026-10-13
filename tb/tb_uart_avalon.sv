`timescale 1ns/1ps
module tb_uart_avalon;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0;
    reg [11:0] av_address=0;
    reg av_read=0, av_write=0;
    reg [31:0] av_writedata=0;
    reg [3:0] av_byteenable=0;
    wire av_waitrequest, av_readdatavalid, av_writeresponsevalid;
    wire [31:0] av_readdata;
    wire [1:0] av_response;
    reg cts_n=0;
    wire tx, rts_n;
    wire rx=tx;
    uart_avalon dut(.*);
    integer checks=0, frames=0;
    integer bits, stop, parity, pattern, n;
    reg [31:0] value, status;
    reg [7:0] payload;
    task check(input bit ok, input string msg);
        begin checks++; if(!ok) $fatal(1,"%s t=%0t",msg,$time); end
    endtask
    task access(input bit wr,input [11:0] addr,input [31:0] data,input [3:0] be,
                input [1:0] expected_response,output [31:0] result);
        integer count;
        begin
            @(negedge clk); av_read=!wr; av_write=wr; av_address=addr;
            av_writedata=data; av_byteenable=be;
            @(posedge clk); while(av_waitrequest) @(posedge clk);
            @(negedge clk); av_read=0; av_write=0;
            count=0;
            while(!(av_readdatavalid || av_writeresponsevalid)) begin
                @(negedge clk); count++;
                if(count>100000) $fatal(1,"Avalon response timeout addr=%h",addr);
            end
            check(av_response===expected_response,"Avalon response code");
            check(av_writeresponsevalid===wr && av_readdatavalid===!wr,"response direction");
            result=av_readdata;
        end
    endtask
    task wr(input [11:0] addr,input [31:0] data);
        reg [31:0] unused;
        access(1,addr,data,15,0,unused);
    endtask
    task rd(input [11:0] addr, output [31:0] data);
        access(0,addr,0,0,0,data);
    endtask
    task poll(input [31:0] mask);
        integer count;
        begin
            count=0; rd(12'hc,status);
            while((status & mask)!=mask) begin
                rd(12'hc,status); count++;
                if(count>20000) $fatal(1,"UART polling timeout");
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); reset_n=1;
        rd(12'hc,value); check(value==1,"reset status");
        // Decode errors and write strobes must survive the generated bus contract.
        access(1,12'hc,0,15,2,value);
        access(0,12'h14,0,0,2,value);
        access(0,12'h104,0,0,2,value);
        access(0,12'h1,0,0,2,value);
        wr(4,3);
        access(1,4,31,0,0,value); rd(4,value); check(value==3,"zero byteenable no-op");
        access(1,4,31,14,0,value); rd(4,value); check(value==3,"upper lanes no-op");
        // CPU-style polling sequence; exact board clock/baud, all 24 formats.
        for(bits=5;bits<=8;bits++) for(stop=0;stop<2;stop++) for(parity=0;parity<3;parity++) begin
            wr(4,(bits-5)|(stop<<2)|(parity==0 ? 0 : 8)|(parity==2 ? 16 : 0));
            for(pattern=0;pattern<4;pattern++) begin
                case(pattern) 0:payload=0; 1:payload=8'hff; 2:payload=8'h55; 3:payload=8'ha6; endcase
                poll(1); wr(0,payload); wr(8,1); poll(3);
                check((status&4)==0,"loopback parity");
                rd(16,value); check(value==(payload & ((1<<bits)-1)),"loopback payload and data masking");
                rd(12,status); check(status==1,"read acknowledges RX");
                frames++;
            end
        end
        // CTS leaves a pending START; bus remains usable for status polling.
        cts_n=1; repeat(5) @(negedge clk);
        wr(4,3); wr(0,8'hb7); wr(8,1);
        repeat(100) @(negedge clk);
        rd(12,status); check((status&1)==0 && tx==1,"CTS blocks transmission");
        rd(8,value); check(value==1,"START pending");
        cts_n=0;
        // RX read is allowed to wait; exactly one response appears when a byte arrives.
        rd(16,value); check(value==8'hb7,"blocking RX read resumes");
        poll(1);
        // Reset a blocking empty RX access, then recover cleanly.
        @(negedge clk); av_read=1; av_address=16;
        @(posedge clk); while(av_waitrequest) @(posedge clk);
        @(negedge clk); av_read=0;
        repeat(20) @(negedge clk);
        check(!av_readdatavalid,"empty RX read waits");
        reset_n=0; repeat(3) @(negedge clk); reset_n=1;
        rd(12,value); check(value==1,"recovery after resetting blocked bus");
        $display("PASS tb_uart_avalon checks=%0d loopback_frames=%0d clock=50MHz baud=115200",checks,frames+1);
        $finish;
    end
    initial begin #30000000; $fatal(1,"UART Avalon watchdog"); end
endmodule
