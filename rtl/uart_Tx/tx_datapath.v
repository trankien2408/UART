`timescale 1ns/1ps
module tx_datapath (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       tick_tx,
    input  wire [7:0] tx_data_i,
    input  wire [1:0] data_bit_num_i,  
    input  wire       parity_en_i,     
    input  wire       parity_type_i,
    
    input  wire       load_tx,
    input  wire       shift_tx,
    input  wire       clr_tick_cnt,
    input  wire [1:0] tx_sel,         
    output wire       tick_max,       
    output wire       bit_cnt_max,    
    output wire       bit_is_parity,  
    output reg        tx
);
    reg [3:0] tick_cnt;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_cnt <= 4'd0;
        end else if (clr_tick_cnt || load_tx) begin
            tick_cnt <= 4'd0;
        end else if (tick_tx) begin
            tick_cnt <= tick_cnt + 1'b1;
        end
    end
    
    assign tick_max = (tick_cnt == 4'd15) && tick_tx;

    reg [7:0] tx_shift_reg;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_shift_reg <= 8'hFF;
        end else if (load_tx) begin
            tx_shift_reg <= tx_data_i;
        end else if (shift_tx) begin
            tx_shift_reg <= {1'b1, tx_shift_reg[7:1]};
        end
    end

    
    // Four bits hold eight DATA bits followed by a PARITY bit.
    reg  [3:0] bit_cnt;
    wire [3:0] max_bit_val;

    assign max_bit_val = 4'd4 + {2'b00, data_bit_num_i};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bit_cnt <= 4'd0;
        end else if (load_tx) begin
            bit_cnt <= 4'd0;
        end else if (shift_tx) begin
            bit_cnt <= bit_cnt + 1'b1;
        end
    end

    assign bit_cnt_max = (bit_cnt == (max_bit_val + (parity_en_i ? 4'd1 : 4'd0)));
    assign bit_is_parity = (bit_cnt == (max_bit_val + 4'd1)) && parity_en_i;

   
    wire calc_parity;
    reg tx_parity_bit;

    assign calc_parity = (data_bit_num_i == 2'b00) ? ^tx_data_i[4:0] :
                         (data_bit_num_i == 2'b01) ? ^tx_data_i[5:0] :
                         (data_bit_num_i == 2'b10) ? ^tx_data_i[6:0] : ^tx_data_i[7:0];

    // Spec: 1 = EVEN, 0 = ODD. Latch parity with the payload.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) tx_parity_bit <= 1'b0;
        else if (load_tx) tx_parity_bit <= parity_type_i ? calc_parity : ~calc_parity;
    end

    always @* begin
        case (tx_sel)
            2'b00:   tx = 1'b0;              
            2'b01:   tx = tx_shift_reg[0];  
            2'b10:   tx = tx_parity_bit;     
            2'b11:   tx = 1'b1;              
            default: tx = 1'b1;
        endcase
    end

endmodule
