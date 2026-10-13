`timescale 1ns/1ps
module rx_datapath (
    input wire clk, reset_n, tick_rx, rx,
    input wire [1:0] data_bit_num_i,
    input wire parity_en_i, parity_type_i,
    input wire shift_rx_en, latch_parity_en, begin_frame, data_phase,
    output wire rx_s, start_rx,
    output wire [3:0] sample_cnt,
    output wire sample_max, rx_bit_cnt_max, bit_is_parity,
    output reg [7:0] rx_data_o,
    output wire parity_error_o
);
    reg rx_ff1, rx_sync, rx_previous;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_ff1 <= 1'b1;
            rx_sync <= 1'b1;
            rx_previous <= 1'b1;
        end else begin
            rx_ff1 <= rx;
            rx_sync <= rx_ff1;
            rx_previous <= rx_sync;
        end
    end
    assign rx_s = rx_sync;
    assign start_rx = rx_previous && !rx_sync;

    reg [3:0] sample_count, bit_count;
    wire [3:0] data_count = 4'd5 + {2'b00, data_bit_num_i};
    wire half_bit = tick_rx && (sample_count == 4'd7);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sample_count <= 4'd0;
            bit_count <= 4'd0;
        end else if (begin_frame) begin
            // Only an accepted START resets timing, never an edge in DATA.
            sample_count <= 4'd0;
            bit_count <= 4'd0;
        end else begin
            if (tick_rx) sample_count <= sample_count + 1'b1;
            if (data_phase && sample_max) bit_count <= bit_count + 1'b1;
        end
    end
    assign sample_cnt = sample_count;
    assign sample_max = tick_rx && (sample_count == 4'd15);
    assign bit_is_parity = parity_en_i && (bit_count == data_count);
    assign rx_bit_cnt_max = (bit_count == (data_count - 4'd1 +
                                            (parity_en_i ? 4'd1 : 4'd0)));

    reg latched_parity;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_data_o <= 8'd0;
            latched_parity <= 1'b0;
        end else if (begin_frame) begin
            rx_data_o <= 8'd0;
            latched_parity <= 1'b0;
        end else begin
            // LSB-first indexing zero-extends 5/6/7-bit characters correctly.
            if (half_bit && shift_rx_en && (bit_count < data_count))
                rx_data_o[bit_count[2:0]] <= rx_sync;
            if (half_bit && latch_parity_en) latched_parity <= rx_sync;
        end
    end
    wire expected_parity = parity_type_i ? (^rx_data_o) : (~^rx_data_o);
    assign parity_error_o = parity_en_i && (latched_parity ^ expected_parity);
endmodule
