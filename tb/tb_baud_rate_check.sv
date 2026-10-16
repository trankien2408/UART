`timescale 1ns/1ps
module baud_case #(parameter integer RATE=115200) (
    input wire clk, rst_n, output reg done=0
);
    localparam integer DIV=50000000/(RATE*16);
    wire tick;
    integer count,last_tick,ticks;
    baud_rate_gen dut(
        .clk(clk),.rst_n(rst_n),.divider_i(16'(DIV)),.reload_i(1'b0),.baud_tick(tick)
    );
    initial begin
        wait(rst_n===1);
        last_tick=0;ticks=0;
        for (count=1;count<=DIV*34;count++) begin
            @(posedge clk);#1;
            if (tick!==((count%DIV)==0)) $fatal(1,"baud %0d incorrect tick at cycle %0d",RATE,count);
            if (tick) begin
                if ((count-last_tick)!=DIV) $fatal(1,"baud %0d interval",RATE);
                last_tick=count;ticks++;
            end
        end
        if(ticks!=34) $fatal(1,"baud %0d missing tick",RATE);
        $display("BAUD PASS rate=%0d divider=%0d ticks=%0d",RATE,DIV,ticks);
        done=1;
    end
    always @(negedge rst_n) begin
        #1;if(tick!==0) $fatal(1,"baud %0d async reset",RATE);
    end
endmodule
module tb_baud_rate_check;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    wire [10:0] done;
    baud_case #(2400)   c0(clk,rst_n,done[0]);
    baud_case #(4800)   c1(clk,rst_n,done[1]);
    baud_case #(9600)   c2(clk,rst_n,done[2]);
    baud_case #(19200)  c3(clk,rst_n,done[3]);
    baud_case #(38400)  c4(clk,rst_n,done[4]);
    baud_case #(57600)  c5(clk,rst_n,done[5]);
    baud_case #(76800)  c6(clk,rst_n,done[6]);
    baud_case #(115200) c7(clk,rst_n,done[7]);
    baud_case #(230400) c8(clk,rst_n,done[8]);
    // Counter-width boundaries DIV=1 and DIV=2, additional to spec rates.
    baud_case #(3125000) c9(clk,rst_n,done[9]);
    baud_case #(1562500) c10(clk,rst_n,done[10]);
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        wait(&done);#3;rst_n=0;#2;
        $display("PASS tb_baud_rate_check 9 spec rates + divider 1/2 boundaries");
        $finish;
    end
    initial begin #2000000;$fatal(1,"baud watchdog");end
endmodule
