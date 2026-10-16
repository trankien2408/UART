`timescale 1ns/1ps
// Integration contract: clk and pclk MUST be the same clock net (no CDC).
// reset_n/presetn are active-low; asserting either resets the entire peripheral.
module dti_uart #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUDRATE = 115200
) (
    input wire clk, reset_n, pclk, presetn,
    input wire psel, penable, pwrite,
    input wire [3:0] pstrb,
    input wire [11:0] paddr,
    input wire [31:0] pwdata,
    output wire pready, pslverr,
    output wire [31:0] prdata,
    input wire rx, cts_n,
    output wire tx, rts_n, irq
);
    wire rst_n = reset_n && presetn;
    wire baud_tick, access, wr, rd_ready, wr_ready, reg_error;
    wire [3:0] strb;
    wire [11:0] addr;
    wire [31:0] wdata, rdata, tx_data;
    wire [7:0] rx_data;
    wire [1:0] data_bits;
    wire stop_bits, parity_en, parity_type, start_tx;
    wire tx_busy, tx_done, rx_done, parity_error, rx_full, core_rts_n;
    wire [15:0] baud_div;
    wire baud_apply, rx_idle;
    reg [4:0] rx_quiet_ticks;
    wire rx_baud_safe = rx_idle && (rx_quiet_ticks==16);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_quiet_ticks<=0;
        else if (baud_apply || !rx_idle) rx_quiet_ticks<=0;
        else if (baud_tick && rx_quiet_ticks<16) rx_quiet_ticks<=rx_quiet_ticks+1'b1;
    end

    // CTS is asynchronous to the FPGA clock. Fail closed while reset is active.
    reg cts_meta, cts_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cts_meta <= 1'b1;
            cts_sync <= 1'b1;
        end else begin
            cts_meta <= cts_n;
            cts_sync <= cts_meta;
        end
    end
    assign rts_n = !rst_n || core_rts_n || rx_full;

    apb_slave u_apb (
        .pclk(pclk), .presetn(rst_n), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pstrb(pstrb), .paddr(paddr), .pwdata(pwdata),
        .pready(pready), .pslverr(pslverr), .prdata(prdata),
        .pwrite_o(wr), .pstrb_o(strb), .paddr_o(addr), .pwdata_o(wdata),
        .access_o(access), .read_en_i(rd_ready), .write_en_i(wr_ready),
        .error_i(reg_error), .prdata_i(rdata)
    );
    register_file #(.DEFAULT_DIV(CLK_FREQ/(16*BAUDRATE))) u_registers (
        .clk(clk), .reset_n(rst_n), .access_i(access), .pwrite_i(wr),
        .pstrb_i(strb), .paddr_i(addr), .pwdata_i(wdata),
        .read_en_o(rd_ready), .write_en_o(wr_ready), .error_o(reg_error),
        .prdata_o(rdata), .tx_data_o(tx_data), .data_bit_num_o(data_bits),
        .stop_bit_num_o(stop_bits), .parity_en_o(parity_en),
        .parity_type_o(parity_type), .start_tx_o(start_tx),
        .tx_busy_i(tx_busy), .tx_done_i(tx_done), .rx_done_i(rx_done),
        .parity_error_i(parity_error), .rx_data_i({24'd0, rx_data}),
        .rx_baud_safe_i(rx_baud_safe), .baud_div_o(baud_div),
        .baud_apply_o(baud_apply), .irq_o(irq), .rx_full_o(rx_full)
    );
    baud_rate_gen u_baud (
        .clk(clk), .rst_n(rst_n), .divider_i(baud_div),
        .reload_i(baud_apply), .baud_tick(baud_tick)
    );
    tx_topmodule u_tx (
        .clk(clk), .reset_n(rst_n), .tick_tx(baud_tick), .tx_data_i(tx_data[7:0]),
        .data_bit_num_i(data_bits), .stop_bit_num_i({1'b0, stop_bits}),
        .parity_en_i(parity_en), .parity_type_i(parity_type),
        .start_tx_i(start_tx), .cts_n(cts_sync), .tx(tx),
        .tx_busy_o(tx_busy), .tx_done_o(tx_done)
    );
    rx_topmodule u_rx (
        .clk(clk), .reset_n(rst_n), .tick_rx(baud_tick), .rx(rx),
        .data_bit_num_i(data_bits), .stop_bit_num_i({1'b0, stop_bits}),
        .parity_en_i(parity_en), .parity_type_i(parity_type),
        .rx_data_o(rx_data), .rx_done_o(rx_done), .parity_error_o(parity_error),
        // Invalid stop-bit frames are discarded inside the RX core.
        .frame_error_o(), .rts_n(core_rts_n), .baud_idle_o(rx_idle)
    );
endmodule
