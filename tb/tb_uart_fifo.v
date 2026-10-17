`timescale 1ns/1ps
module fifo_trial #(parameter DEPTH=16)(output reg done=0);
    reg clk=0; always #5 clk=~clk;
    reg reset_n=0,push=0,pop=0;
    reg [7:0] data_i=0;
    wire [7:0] data_o;
    wire full,empty;
    wire [$clog2(DEPTH+1)-1:0] count;
    reg [7:0] model[0:DEPTH-1];
    integer n=0,seed=DEPTH,unused;
    reg take,put;
    uart_fifo #(.DEPTH(DEPTH)) dut(.*);
    initial begin
        unused=$urandom(seed);
        repeat(3) @(negedge clk);reset_n=1;
        for(integer i=0;i<10000;i++) begin
            @(negedge clk);push=$urandom;pop=$urandom;data_i=$urandom;
            reset_n=(i%137!=0);
            if(!reset_n) n=0;
            #1;
            if(count!==n || full!==(n==DEPTH) || empty!==(n==0)) $fatal(1,"FIFO depth %0d flags",DEPTH);
            if(n>0 && data_o!==model[0]) $fatal(1,"FIFO depth %0d order",DEPTH);
            if(reset_n) begin
                take=pop && n>0;put=push && (n<DEPTH || take);
                if(take) begin for(integer j=0;j<n-1;j++) model[j]=model[j+1];n--;end
                if(put) begin model[n]=data_i;n++;end
            end
            @(posedge clk);#1;
            if(count!==n) $fatal(1,"FIFO depth %0d count",DEPTH);
        end
        done=1;
    end
endmodule
module tb_uart_fifo;
    wire d1,d3,d16;
    fifo_trial #(.DEPTH(1)) a(d1);
    fifo_trial #(.DEPTH(3)) b(d3);
    fifo_trial #(.DEPTH(16)) c(d16);
    initial begin wait(d1&&d3&&d16);$display("PASS tb_uart_fifo 30000 random cycles depths 1/3/16, wrap, reset, simultaneous push/pop");$finish;end
    initial begin #200000;$fatal(1,"watchdog");end
endmodule
