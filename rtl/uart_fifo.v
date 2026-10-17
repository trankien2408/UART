`timescale 1ns/1ps
module uart_fifo #(parameter WIDTH=8, parameter DEPTH=16) (
    input wire clk, reset_n, push, pop,
    input wire [WIDTH-1:0] data_i,
    output wire [WIDTH-1:0] data_o,
    output wire full, empty,
    output reg [$clog2(DEPTH+1)-1:0] count
);
    localparam PW = (DEPTH>1) ? $clog2(DEPTH) : 1;
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PW-1:0] rd_ptr, wr_ptr;
    wire take = pop && !empty;
    wire put = push && (!full || take);
    assign full = count == DEPTH;
    assign empty = count == 0;
    assign data_o = empty ? {WIDTH{1'b0}} : mem[rd_ptr];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_ptr <= 0; wr_ptr <= 0; count <= 0;
        end else begin
            if (put) begin
                mem[wr_ptr] <= data_i;
                wr_ptr <= (wr_ptr == DEPTH-1) ? {PW{1'b0}} : wr_ptr+1'b1;
            end
            if (take) rd_ptr <= (rd_ptr == DEPTH-1) ? {PW{1'b0}} : rd_ptr+1'b1;
            case ({put,take})
                2'b10: count <= count+1'b1;
                2'b01: count <= count-1'b1;
                default: begin end
            endcase
        end
    end
endmodule
