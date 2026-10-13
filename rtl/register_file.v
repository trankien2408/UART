`timescale 1ns/1ps
// Register map follows 7up_uart.drawio.pdf. All addresses are BYTE offsets.
// read_en_o/write_en_o mean READY, not a write strobe. access_i qualifies commit.
module register_file (
    input wire clk, reset_n,
    input wire access_i, pwrite_i,
    input wire [3:0] pstrb_i,
    input wire [11:0] paddr_i,
    input wire [31:0] pwdata_i,
    output reg read_en_o, write_en_o, error_o,
    output reg [31:0] prdata_o,
    output wire [31:0] tx_data_o,
    output wire [1:0] data_bit_num_o,
    output wire stop_bit_num_o, parity_en_o, parity_type_o,
    output reg start_tx_o,
    input wire tx_busy_i, tx_done_i, rx_done_i, parity_error_i,
    input wire [31:0] rx_data_i,
    output wire rx_pending_o
);
    localparam [11:0] REG_TX = 12'h000, REG_CFG = 12'h004,
        REG_CTRL = 12'h008, REG_STT = 12'h00c, REG_RX = 12'h010;
    reg [7:0] tx_data_reg, rx_data_reg;
    reg [4:0] cfg_reg;
    reg tx_done, rx_done, parity_error;
    wire known_addr = (paddr_i == REG_TX) || (paddr_i == REG_CFG) ||
                      (paddr_i == REG_CTRL) || (paddr_i == REG_STT) ||
                      (paddr_i == REG_RX);
    wire read_commit = access_i && !pwrite_i && read_en_o && !error_o;
    wire write_commit = access_i && pwrite_i && write_en_o && !error_o;
    wire consume_rx = read_commit && (paddr_i == REG_RX);

    assign tx_data_o = {24'd0, tx_data_reg};
    assign data_bit_num_o = cfg_reg[1:0];
    assign stop_bit_num_o = cfg_reg[2];
    assign parity_en_o = cfg_reg[3];
    assign parity_type_o = cfg_reg[4];
    assign rx_pending_o = rx_done;

    always @(*) begin
        error_o = !known_addr || (pwrite_i &&
                  ((paddr_i == REG_STT) || (paddr_i == REG_RX)));
        read_en_o = 1'b1;
        write_en_o = 1'b1;
        prdata_o = 32'd0;
        case (paddr_i)
            REG_TX: begin
                prdata_o = {24'd0, tx_data_reg};
                // Keep the current character stable while queued/waiting for CTS.
                if (pstrb_i[0]) write_en_o = tx_done;
            end
            REG_CFG: prdata_o = {27'd0, cfg_reg};
            REG_CTRL: begin
                prdata_o = {31'd0, start_tx_o};
                if (pstrb_i[0] && pwdata_i[0]) write_en_o = tx_done;
            end
            REG_STT: prdata_o = {29'd0, parity_error, rx_done, tx_done};
            REG_RX: begin
                prdata_o = {24'd0, rx_data_reg};
                read_en_o = rx_done;
            end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_data_reg <= 8'd0;
            rx_data_reg <= 8'd0;
            cfg_reg <= 5'd0;
            start_tx_o <= 1'b0;
            tx_done <= 1'b1;
            rx_done <= 1'b0;
            parity_error <= 1'b0;
        end else begin
            if (tx_busy_i) start_tx_o <= 1'b0;
            if (tx_done_i) tx_done <= 1'b1;
            if (write_commit && pstrb_i[0]) begin
                case (paddr_i)
                    REG_TX: tx_data_reg <= pwdata_i[7:0];
                    REG_CFG: cfg_reg <= pwdata_i[4:0];
                    REG_CTRL: if (pwdata_i[0]) begin
                        start_tx_o <= 1'b1;
                        tx_done <= 1'b0;
                    end
                    default: begin end
                endcase
            end
            if (consume_rx) begin
                rx_done <= 1'b0;
                parity_error <= 1'b0;
            end
            // One-entry RX buffer. Never overwrite unread data. If a read and
            // completion coincide, the CPU gets the OLD byte and the NEW one stays.
            if (rx_done_i && (!rx_done || consume_rx)) begin
                rx_data_reg <= rx_data_i[7:0];
                parity_error <= parity_error_i;
                rx_done <= 1'b1;
            end
        end
    end
endmodule
