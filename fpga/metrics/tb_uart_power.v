`timescale 1ns/1ps
module tb_uart_power;
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
    wire irq;
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
        wr(4,3); // 8N1, default divider 27: 115740.74 baud at 50 MHz.
        wr(12'h024,7); // all three implemented interrupt sources enabled.
        repeat(10) @(negedge clk);
        $dumpfile("activity.vcd");
        $dumpvars(0,dut);
        for(n=0;n<32;n=n+1) begin
            case(n%4)
                0:payload=8'h00; 1:payload=8'hff;
                2:payload=8'h55; 3:payload=8'ha6;
            endcase
            poll(1); wr(0,payload); wr(8,1); poll(3);
            rd(16,value); check(value==payload,"power workload loopback payload");
            frames++;
        end
        $display("PASS power activity: %0d checked 8N1 loopback frames, 50MHz, divider=27; MMIO polling, IRQ enabled",frames);
        $finish;
    end
    initial begin #10000000; $fatal(1,"power activity watchdog"); end
endmodule
