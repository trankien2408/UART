`timescale 1ns/1ps
module tb_baud_dynamic;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,reload_i=0;
    reg [15:0] divider_i=27;
    wire baud_tick;
    baud_rate_gen dut(.*);
    integer checks=0;
    task test_div(input [15:0] div);
        @(negedge clk);divider_i=div;reload_i=1;
        @(posedge clk);#1;if(baud_tick!==0)$fatal(1,"reload must clear tick");
        @(negedge clk);reload_i=0;
        for(integer c=1;c<=(div ? div*4 : 20);c++) begin
            @(posedge clk);#1;checks++;
            if(baud_tick!==((div!=0) && (c%div==0)))$fatal(1,"divider %0d cycle %0d",div,c);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        test_div(1);test_div(2);test_div(3);test_div(27);test_div(326);
        test_div(65535);test_div(0);test_div(54);test_div(1);
        #2;rst_n=0;#1;if(baud_tick!==0)$fatal(1,"async reset");
        $display("PASS tb_baud_dynamic checks=%0d reload, zero fail-closed, divider 1/2/65535, live changes",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"watchdog");end
endmodule
