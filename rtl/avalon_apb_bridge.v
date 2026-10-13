`timescale 1ns/1ps
// One outstanding, non-burst Avalon-MM command. Byte-addressed APB4.
// Commands are accepted in IDLE; responses are returned after APB completion.
// Blocking APB accesses remain blocking. Reset must also reset the APB slave.
module avalon_apb_bridge (
    input wire clk, reset_n,
    input wire [11:0] av_address,
    input wire av_read, av_write,
    input wire [31:0] av_writedata,
    input wire [3:0] av_byteenable,
    output wire av_waitrequest,
    output reg [31:0] av_readdata,
    output wire av_readdatavalid, av_writeresponsevalid,
    output reg [1:0] av_response,
    output wire psel, penable,
    output reg pwrite,
    output reg [11:0] paddr,
    output reg [31:0] pwdata,
    output reg [3:0] pstrb,
    input wire pready, pslverr,
    input wire [31:0] prdata
);
    localparam IDLE=2'd0, SETUP=2'd1, ACCESS=2'd2, RESPONSE=2'd3;
    reg [1:0] state;
    assign av_waitrequest = !reset_n || state != IDLE;
    assign av_readdatavalid = reset_n && state == RESPONSE && !pwrite;
    assign av_writeresponsevalid = reset_n && state == RESPONSE && pwrite;
    assign psel = reset_n && (state == SETUP || state == ACCESS);
    assign penable = reset_n && state == ACCESS;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            pwrite <= 0; paddr <= 0; pwdata <= 0; pstrb <= 0;
            av_readdata <= 0; av_response <= 0;
        end else begin
            case (state)
                IDLE: if (av_read || av_write) begin
                    pwrite <= av_write;
                    paddr <= av_address;
                    pwdata <= av_writedata;
                    pstrb <= av_write ? av_byteenable : 4'd0;
                    if (av_read && av_write) begin
                        // Illegal command: return SLAVEERROR without APB effects.
                        av_response <= 2'b10;
                        av_readdata <= 0;
                        state <= RESPONSE;
                    end else state <= SETUP;
                end
                SETUP: state <= ACCESS;
                ACCESS: if (pready) begin
                    av_readdata <= pslverr ? 32'd0 : prdata;
                    av_response <= pslverr ? 2'b10 : 2'b00;
                    state <= RESPONSE;
                end
                RESPONSE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
