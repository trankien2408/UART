`timescale 1ns/1ps
// divider_i is the number of system clocks per x16 tick (1..65535).
// Change divider only together with reload_i while both serial engines are idle.
module baud_rate_gen #(
    parameter CLK_FREQ=50000000, BAUD_RATE=9600, OVERSAMPLE=16
)(
    input wire clk, rst_n,
    input wire [15:0] divider_i,
    input wire reload_i,
    output reg baud_tick
);
    reg [15:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin counter<=0; baud_tick<=0; end
        else if (reload_i || divider_i==0) begin counter<=0; baud_tick<=0; end
        else if (counter >= divider_i-16'd1) begin counter<=0; baud_tick<=1; end
        else begin counter<=counter+16'd1; baud_tick<=0; end
    end
endmodule
