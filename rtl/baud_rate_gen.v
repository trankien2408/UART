// =============================================================================
// Module Name:  baud_rate_gen
// Description:  Baud Rate Generator với bộ đếm chia tần số tự động tính toán.
//               Tạo xung oversampling x16 (baud_tick) phục vụ đồng bộ cho cả
//               khối UART RX và UART TX.
// =============================================================================

`timescale 1ns / 1ps

module baud_rate_gen #(
    parameter CLK_FREQ   = 50_000_000, // Tần số xung clock hệ thống (Hz), mặc định 50 MHz
    parameter BAUD_RATE  = 9600,       // Tốc độ Baud mong muốn (bps), mặc định 9600 bps
    parameter OVERSAMPLE = 16          // Hệ số Oversampling (mặc định x16 cho UART RX/TX)
)(
    input  wire clk,       // Xung clock hệ thống
    input  wire rst_n,     // Reset bất đồng bộ, tích cực mức thấp (active low)
    output reg  baud_tick  // Xung baud rate tick x16 oversampling (tích cực mức cao 1 chu kỳ clock)
);

    // -------------------------------------------------------------------------
    // 1. Tính toán giá trị chia xung và độ rộng bộ đếm
    // -------------------------------------------------------------------------
    // Tần số xung tick mong muốn: f_tick = BAUD_RATE * OVERSAMPLE
    // Số chu kỳ clock cho mỗi tick: DIV_VAL = CLK_FREQ / (BAUD_RATE * OVERSAMPLE)
    // Ví dụ với CLK_FREQ = 50 MHz, BAUD_RATE = 9600, OVERSAMPLE = 16:
    // DIV_VAL = 50,000,000 / (9600 * 16) = 50,000,000 / 153,600 = 325 (lấy phần nguyên)
    // Chu kỳ tick = 325 chu kỳ clock = 325 * 20ns = 6.5 us
    // Chu kỳ 1 bit UART = 16 * 6.5 us = 104 us (~9615.4 bps, sai số ~0.16% < 2%)
    localparam DIV_VAL   = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    
    // Tự động xác định độ rộng bit cho thanh ghi bộ đếm
    localparam CNT_WIDTH = (DIV_VAL > 1) ? $clog2(DIV_VAL) : 1;

    // -------------------------------------------------------------------------
    // 2. Thanh ghi bộ đếm chu kỳ clock
    // -------------------------------------------------------------------------
    reg [CNT_WIDTH-1:0] counter;

    // -------------------------------------------------------------------------
    // 3. Logic tuần tự đếm và phát xung baud_tick
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter   <= {CNT_WIDTH{1'b0}};
            baud_tick <= 1'b0;
        end else begin
            if (counter == (DIV_VAL - 1)) begin
                counter   <= {CNT_WIDTH{1'b0}};
                baud_tick <= 1'b1; // Kích mức cao trong đúng 1 chu kỳ clock
            end else begin
                counter   <= counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

endmodule

