`timescale 1ns/1ps
module rx_controller (
    input wire clk, reset_n, tick_rx, start_rx, rx_s,
    input wire [3:0] sample_cnt,
    input wire sample_max, rx_bit_cnt_max, bit_is_parity, parity_en_i,
    input wire [1:0] stop_bit_num_i,
    output reg shift_rx_en, latch_parity_en, rts_n, rx_done_o, frame_error_o,
    output wire begin_frame, data_phase
);
    localparam S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;
    reg [1:0] current_state, next_state;
    reg stop_cnt, has_frame_error;
    wire half_bit = tick_rx && (sample_cnt == 4'd7);
    wire last_stop = (stop_bit_num_i != 2'b01) || stop_cnt;
    assign begin_frame = (current_state == S_IDLE) && start_rx;
    assign data_phase = (current_state == S_DATA);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= S_IDLE;
            stop_cnt <= 1'b0;
            has_frame_error <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state != S_STOP) stop_cnt <= 1'b0;
            else if (sample_max) stop_cnt <= 1'b1;
            if (begin_frame) has_frame_error <= 1'b0;
            else if ((current_state == S_STOP) && half_bit && !rx_s)
                has_frame_error <= 1'b1;
        end
    end

    always @* begin
        next_state = current_state;
        shift_rx_en = 1'b0;
        latch_parity_en = 1'b0;
        rts_n = 1'b1;
        rx_done_o = 1'b0;
        frame_error_o = 1'b0;
        case (current_state)
            S_IDLE: begin
                rts_n = 1'b0;
                if (start_rx) next_state = S_START;
            end
            S_START: begin
                // Reject a short LOW glitch instead of treating it as a frame.
                if (half_bit && rx_s) next_state = S_IDLE;
                else if (sample_max) next_state = S_DATA;
            end
            S_DATA: begin
                shift_rx_en = !bit_is_parity;
                latch_parity_en = parity_en_i && bit_is_parity;
                if (sample_max && rx_bit_cnt_max) next_state = S_STOP;
            end
            S_STOP: if (half_bit) begin
                frame_error_o = !rx_s || has_frame_error;
                if (last_stop) begin
                    rx_done_o = rx_s && !has_frame_error;
                    // Rearm at the centre of the final stop bit to allow
                    // consecutive frames even when the sender is faster.
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end
endmodule
