`timescale 1ns/1ps
module de2_115_uart_top (
    input wire CLOCK_50,
    input wire KEY0,
    input wire UART_RX, UART_CTS_N,
    output wire UART_TX, UART_RTS_N,
    output wire [1:0] LEDG
);
    // Cyclone IV implements initial register values at configuration time.
    // Hold reset for 16 clocks on power-up and after each KEY0 assertion.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [15:0] reset_release = 16'd0;
    always @(posedge CLOCK_50 or negedge KEY0) begin
        if (!KEY0) reset_release <= 16'd0;
        else reset_release <= {reset_release[14:0], 1'b1};
    end
    wire [3:0] control;
    wire uart_tx;
    // Firmware changes routing only when TX is idle and drains old RX data.
    wire uart_rx = control[0] ? uart_tx : UART_RX;
    wire uart_cts_n = (control[1] && !control[0]) ? UART_CTS_N : 1'b0;
    // Internal self-tests must not transmit their test bytes to external hardware.
    assign UART_TX = control[0] ? 1'b1 : uart_tx;
    assign LEDG = control[3:2];
    uart_soc soc (
        .clk_clk(CLOCK_50), .reset_reset_n(reset_release[15]),
        .control_export(control),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .uart_cts_n(uart_cts_n), .uart_rts_n(UART_RTS_N)
    );
endmodule
