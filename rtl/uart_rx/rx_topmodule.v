`timescale 1ns/1ps
module rx_topmodule (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       tick_rx,
    input  wire       rx,
    
    // Tín hiệu cấu hình ngoại vi
    input  wire [1:0] data_bit_num_i,
    input  wire [1:0] stop_bit_num_i,
    input  wire       parity_en_i,
    input  wire       parity_type_i,
    
    // Tín hiệu ngõ ra
    output wire [7:0] rx_data_o,
    output wire       rx_done_o,
    output wire       parity_error_o,
    output wire       frame_error_o,
    output wire       baud_idle_o,
    output wire       rts_n
);

    wire       start_rx_w;
    wire       rx_s_w;
    wire [3:0] sample_cnt_w;
    wire       sample_max_w;
    wire       rx_bit_cnt_max_w;
    wire       bit_is_parity_w;
    wire       shift_rx_en_w;
    wire       latch_parity_en_w;
    wire       begin_frame_w, data_phase_w;
    assign baud_idle_o = !rts_n && rx_s_w && !start_rx_w;
    reg [5:0] frame_cfg;
    wire [5:0] cfg = rts_n ? frame_cfg :
        {stop_bit_num_i, parity_type_i, parity_en_i, data_bit_num_i};
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) frame_cfg <= 6'd0;
        else if (begin_frame_w)
            frame_cfg <= {stop_bit_num_i, parity_type_i, parity_en_i, data_bit_num_i};
    end

    // Kết nối khối Datapath
    rx_datapath u_rx_datapath (
        .clk             (clk),
        .reset_n         (reset_n),
        .tick_rx         (tick_rx),
        .rx              (rx),
        .data_bit_num_i  (cfg[1:0]),
        .parity_en_i     (cfg[2]),
        .parity_type_i   (cfg[3]),
        .begin_frame    (begin_frame_w),
        .data_phase     (data_phase_w),
        .shift_rx_en     (shift_rx_en_w),
        .latch_parity_en (latch_parity_en_w),
        .rx_s            (rx_s_w),
        .start_rx        (start_rx_w),
        .sample_cnt      (sample_cnt_w),
        .sample_max      (sample_max_w),
        .rx_bit_cnt_max  (rx_bit_cnt_max_w),
        .bit_is_parity   (bit_is_parity_w),
        .rx_data_o       (rx_data_o),
        .parity_error_o  (parity_error_o)
    );

    // Kết nối khối FSM Controller
    rx_controller u_rx_controller (
        .clk             (clk),
        .reset_n         (reset_n),
        .tick_rx         (tick_rx),
        .start_rx        (start_rx_w),
        .rx_s            (rx_s_w),
        .sample_cnt      (sample_cnt_w),
        .sample_max      (sample_max_w),
        .rx_bit_cnt_max  (rx_bit_cnt_max_w),
        .bit_is_parity   (bit_is_parity_w),
        .parity_en_i     (cfg[2]),
        .stop_bit_num_i  (cfg[5:4]),
        .begin_frame    (begin_frame_w),
        .data_phase     (data_phase_w),
        .shift_rx_en     (shift_rx_en_w),
        .latch_parity_en (latch_parity_en_w),
        .rts_n           (rts_n),
        .rx_done_o       (rx_done_o),
        .frame_error_o   (frame_error_o)
    );

endmodule
