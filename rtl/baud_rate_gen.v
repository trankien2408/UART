`timescale 1ns/1ps
// divider_i is the number of system clocks per x16 tick (1..65535).
// Change divider only together with reload_i while both serial engines are idle.
module baud_rate_gen (
    input wire clk, rst_n,
    input wire [15:0] divider_i,
    input wire reload_i,
    output reg tick_tx,
    output wire tick_rx
);
    // Separate output ports; both directions use the same active divider/phase.
    assign tick_rx = tick_tx;
    reg [15:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin counter<=0; tick_tx<=0; end
        else if (reload_i || divider_i==0) begin counter<=0; tick_tx<=0; end
        else if (counter >= divider_i-16'd1) begin counter<=0; tick_tx<=1; end
        else begin counter<=counter+16'd1; tick_tx<=0; end
    end
endmodule
