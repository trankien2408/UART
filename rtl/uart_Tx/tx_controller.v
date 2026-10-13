`timescale 1ns/1ps
module tx_controller (
    input  wire       clk,
    input  wire       reset_n,
    
    // Tín hiệu ngoại vi & Cấu hình
    input  wire       start_tx_i,
    input  wire       cts_n,
    input  wire       parity_en_i,
    input  wire       bit_is_parity,
    input  wire [1:0] stop_bit_num_i,
     
    // Tín hiệu phản hồi từ Datapath
    input  wire       tick_max,
    input  wire       bit_cnt_max,
    
    // Tín hiệu điều khiển ngõ ra cho Datapath
    output reg        clr_tick_cnt,
    output reg  [1:0] tx_sel,
    output reg        load_tx,
    output reg        shift_tx,
    
    // Tín hiệu gửi ra Top Module
    output reg        tx_busy_o,
    output reg        tx_done_o   
);

    localparam S_IDLE  = 2'b00;
    localparam S_START = 2'b01;
    localparam S_DATA  = 2'b10;
    localparam S_STOP  = 2'b11;

    reg [1:0] current_state, next_state;
    reg [1:0] stop_cnt;
    wire [1:0] max_stop_val;

    // Gán giá trị giới hạn đếm Bit STOP: 2'b00 -> 0 (1 bit), 2'b01 -> 1 (2 bit)
    assign max_stop_val = (stop_bit_num_i == 2'b01) ? 2'd1 : 2'd0;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            stop_cnt <= 2'd0;
        end 
        else if (current_state != S_STOP) begin
            stop_cnt <= 2'd0; 
        end
        else if (current_state == S_STOP && tick_max) begin
            stop_cnt <= stop_cnt + 1'b1; 
        end
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end
 
    always @* begin
        // Giá trị mặc định
        next_state   = current_state;
        tx_busy_o    = 1'b1;
        tx_done_o    = 1'b0;
        load_tx      = 1'b0;
        shift_tx     = 1'b0;
        clr_tick_cnt = 1'b0;
        tx_sel       = 2'b11;

        case (current_state)
            S_IDLE: begin
                tx_busy_o    = 1'b0;
                tx_done_o    = 1'b0;
                load_tx      = 1'b0;
                shift_tx     = 1'b0;
                clr_tick_cnt = 1'b1;
                tx_sel       = 2'b11;

                if (start_tx_i && (!cts_n)) begin
                    load_tx    = 1'b1;
                    next_state = S_START;
                end
            end

            S_START: begin
                tx_busy_o    = 1'b1;
                tx_sel       = 2'b00;

                if (tick_max) begin
                    next_state = S_DATA;
                end
            end

            S_DATA: begin
                tx_busy_o    = 1'b1;
                shift_tx     = tick_max ? 1'b1 : 1'b0;
                clr_tick_cnt = tick_max ? 1'b1 : 1'b0;
                tx_sel       = (parity_en_i && bit_is_parity) ? 2'b10 : 2'b01;

                if (bit_cnt_max && tick_max) begin
                    next_state = S_STOP;
                end
            end

            S_STOP: begin
                tx_busy_o = 1'b1;
                tx_sel    = 2'b11; 
                if (tick_max && (stop_cnt == max_stop_val)) begin
                    tx_done_o  = 1'b1;
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE; 
        endcase
    end
endmodule
