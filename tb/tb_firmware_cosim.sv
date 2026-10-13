`timescale 1ns/1ps
module tb_firmware_cosim;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0;
    reg [11:0] av_address=0;
    reg av_read=0, av_write=0;
    reg [31:0] av_writedata=0;
    reg [3:0] av_byteenable=0;
    wire av_waitrequest, av_readdatavalid, av_writeresponsevalid;
    wire [31:0] av_readdata;
    wire [1:0] av_response;
    wire cts_n=0;
    wire tx, rts_n;
    wire rx=tx;
    uart_avalon dut(.*);
    reg accepted=0, rvalid=0, wvalid=0;
    reg [31:0] rdata=0, cycles=0;
    reg [1:0] response=0;
    always @(posedge clk) begin
        cycles<=cycles+1;
        accepted<=reset_n && (av_read || av_write) && !av_waitrequest;
        rvalid<=av_readdatavalid; wvalid<=av_writeresponsevalid;
        rdata<=av_readdata; response<=av_response;
    end
    always @(negedge clk) if(reset_n)
        $firmware_tick(av_address,av_read,av_write,av_writedata,av_byteenable,
                       accepted,rvalid,wvalid,rdata,response,cycles);
    initial begin
        $firmware_start;
        repeat(5) @(posedge clk); #1; reset_n=1;
    end
    initial begin #50000000; $fatal(1,"firmware co-simulation watchdog"); end
endmodule
