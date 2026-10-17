`timescale 1ns/1ps
module apb_slave (
    input wire pclk, presetn,
    input wire psel, penable, pwrite,
    input wire [3:0] pstrb,
    input wire [11:0] paddr,
    input wire [31:0] pwdata,
    output wire pready, pslverr,
    output wire [31:0] prdata,
    output reg pwrite_o,
    output reg [3:0] pstrb_o,
    output reg [11:0] paddr_o,
    output reg [31:0] pwdata_o,
    output wire access_o,
    input wire read_en_i, write_en_i, error_i,
    input wire [31:0] prdata_i
);
    localparam IDLE = 2'd0, SETUP = 2'd1, ACCESS = 2'd2;
    reg [1:0] state;

    assign access_o = presetn && (state == ACCESS) && psel && penable;
    assign pready = access_o && (error_i || (pwrite_o ? write_en_i : read_en_i));
    assign pslverr = pready && error_i;
    assign prdata = (access_o && !pwrite_o && !error_i) ? prdata_i : 32'd0;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state <= IDLE;
            pwrite_o <= 1'b0;
            pstrb_o <= 4'd0;
            paddr_o <= 12'd0;
            pwdata_o <= 32'd0;
        end else begin
            case (state)
                IDLE: if (psel && !penable) begin
                    pwrite_o <= pwrite;
                    pstrb_o <= pstrb;
                    paddr_o <= paddr;
                    pwdata_o <= pwdata;
                    state <= SETUP;
                end
                SETUP: begin
                    if (!psel) state <= IDLE;
                    else if (penable) state <= ACCESS;
                end
                ACCESS: begin
                    if (!psel || pready) state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
