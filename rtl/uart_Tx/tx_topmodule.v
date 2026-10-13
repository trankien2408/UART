`timescale 1ns/1ps
module tx_topmodule (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       tick_tx,
    input  wire [7:0] tx_data_i,
    input  wire [1:0] data_bit_num_i,
    input  wire [1:0] stop_bit_num_i, 
    input  wire       parity_en_i,
    input  wire       parity_type_i,
    
    // Tín hiệu điều khiển & Báo trạng thái
    input  wire       start_tx_i,
    input  wire       cts_n,
    output wire       tx,
    output wire       tx_busy_o,
    output wire       tx_done_o
);
    wire       clr_tick_cnt;
    wire [1:0] tx_sel;
    wire       load_tx;
    wire       shift_tx;
    wire       tick_max;
    wire       bit_cnt_max;
    wire       bit_is_parity;
    // Freeze the frame format at the actual start (after CTS permits it).
    reg [5:0] frame_cfg;
    wire [5:0] cfg = tx_busy_o ? frame_cfg :
        {stop_bit_num_i, parity_type_i, parity_en_i, data_bit_num_i};
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) frame_cfg <= 6'd0;
        else if (load_tx)
            frame_cfg <= {stop_bit_num_i, parity_type_i, parity_en_i, data_bit_num_i};
    end
    // 1. Khối Datapath (tx_datapath)
   tx_datapath u_tx_datapath (
        .clk            (clk),
        .reset_n        (reset_n),
        .tick_tx        (tick_tx),
        .clr_tick_cnt   (clr_tick_cnt),
        .tx_data_i      (tx_data_i),
        .data_bit_num_i (cfg[1:0]),
        .parity_en_i    (cfg[2]),
        .parity_type_i  (cfg[3]),
        .load_tx        (load_tx),
        .shift_tx       (shift_tx),
        .tx_sel         (tx_sel),
        .tick_max       (tick_max),
        .bit_cnt_max    (bit_cnt_max),
        .bit_is_parity  (bit_is_parity),
        .tx             (tx)
    );
    // 2. Khối Controller (tx_controller)
    tx_controller u_tx_controller (
        .clk            (clk),
        .reset_n        (reset_n),
        .start_tx_i     (start_tx_i),
        .cts_n          (cts_n),
        .parity_en_i    (cfg[2]),
        .bit_is_parity  (bit_is_parity),
        .stop_bit_num_i (cfg[5:4]),
        .tick_max       (tick_max),
        .bit_cnt_max    (bit_cnt_max),
        .clr_tick_cnt   (clr_tick_cnt),
        .tx_sel         (tx_sel),
        .load_tx        (load_tx),
        .shift_tx       (shift_tx),
        .tx_busy_o      (tx_busy_o),
        .tx_done_o      (tx_done_o)
    );

endmodule
