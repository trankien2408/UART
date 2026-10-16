`timescale 1ns/1ps
module uart_avalon #(
    parameter integer CLK_FREQ=50000000,
    parameter integer BAUDRATE=115200
) (
    input wire clk, reset_n,
    input wire [11:0] av_address,
    input wire av_read, av_write,
    input wire [31:0] av_writedata,
    input wire [3:0] av_byteenable,
    output wire av_waitrequest,
    output wire [31:0] av_readdata,
    output wire av_readdatavalid, av_writeresponsevalid,
    output wire [1:0] av_response,
    input wire rx, cts_n,
    output wire tx, rts_n, irq
);
    wire psel, penable, pwrite, pready, pslverr;
    wire [11:0] paddr;
    wire [31:0] pwdata, prdata;
    wire [3:0] pstrb;
    avalon_apb_bridge bridge (
        .clk(clk), .reset_n(reset_n), .av_address(av_address),
        .av_read(av_read), .av_write(av_write), .av_writedata(av_writedata),
        .av_byteenable(av_byteenable), .av_waitrequest(av_waitrequest),
        .av_readdata(av_readdata), .av_readdatavalid(av_readdatavalid),
        .av_writeresponsevalid(av_writeresponsevalid), .av_response(av_response),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .pstrb(pstrb), .pready(pready), .pslverr(pslverr), .prdata(prdata)
    );
    dti_uart #(.CLK_FREQ(CLK_FREQ), .BAUDRATE(BAUDRATE)) uart (
        .clk(clk), .pclk(clk), .reset_n(reset_n), .presetn(reset_n),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .pstrb(pstrb), .pready(pready), .pslverr(pslverr),
        .prdata(prdata), .rx(rx), .tx(tx), .cts_n(cts_n), .rts_n(rts_n), .irq(irq)
    );
endmodule
