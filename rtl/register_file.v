`timescale 1ns/1ps
// Register map follows 7up_uart.drawio.pdf. All addresses are BYTE offsets.
// read_en_o/write_en_o mean READY, not a write strobe. access_i qualifies commit.
module register_file #(parameter FIFO_DEPTH=16, parameter DEFAULT_DIV=27) (
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
    input wire rx_baud_safe_i,
    output reg [15:0] baud_div_o,
    output wire baud_apply_o, irq_o,
    output wire rx_pending_o, rx_full_o
);
    localparam [11:0] REG_TX=12'h000, REG_CFG=12'h004,
        REG_CTRL=12'h008, REG_STT=12'h00c, REG_RX=12'h010,
        REG_FIFO=12'h014, REG_BAUD_SHADOW=12'h018, REG_BAUD_ACTIVE=12'h01c,
        REG_BAUD_CTRL=12'h020, REG_INT_EN=12'h024, REG_INT_ST=12'h028;
    localparam IDLE=0, WAIT_BUSY=1, RUN=2;
    reg [1:0] tx_state;
    reg [7:0] tx_data_reg, tx_active, rx_last;
    reg [4:0] cfg_reg;
    reg rx_overrun;
    reg [15:0] baud_shadow;
    reg baud_rejected;
    reg [2:0] int_enable;
    wire tx_full, tx_empty, rx_empty;
    wire [$clog2(FIFO_DEPTH+1)-1:0] tx_count, rx_count;
    wire [7:0] tx_head;
    wire [8:0] rx_head;
    wire tx_done = tx_empty && (tx_state==IDLE) && !tx_busy_i;
    wire rx_done = !rx_empty;
    wire parity_error = !rx_empty && rx_head[8];
    wire [2:0] int_status = {rx_overrun, tx_done, rx_done};
    wire baud_safe = tx_done && rx_baud_safe_i;
    assign irq_o = reset_n && (|(int_enable & int_status));
    wire known_addr = (paddr_i==REG_TX)||(paddr_i==REG_CFG)||
        (paddr_i==REG_CTRL)||(paddr_i==REG_STT)||(paddr_i==REG_RX)||
        (paddr_i==REG_FIFO)||(paddr_i==REG_BAUD_SHADOW)||
        (paddr_i==REG_BAUD_ACTIVE)||(paddr_i==REG_BAUD_CTRL)||
        (paddr_i==REG_INT_EN)||(paddr_i==REG_INT_ST);
    wire read_commit = access_i && !pwrite_i && read_en_o && !error_o;
    wire write_commit = access_i && pwrite_i && write_en_o && !error_o;
    wire consume_rx = read_commit && (paddr_i==REG_RX);
    wire enqueue_tx = write_commit && pstrb_i[0] && (paddr_i==REG_CTRL) && pwdata_i[0];
    wire apply_request = write_commit && pstrb_i[0] &&
        (paddr_i==REG_BAUD_CTRL) && pwdata_i[2];
    assign baud_apply_o = apply_request && baud_safe && (baud_shadow!=0);
    wire take_tx = (tx_state==IDLE) && !tx_busy_i && !tx_empty;
    uart_fifo #(.WIDTH(8),.DEPTH(FIFO_DEPTH)) tx_fifo (
        .clk(clk),.reset_n(reset_n),.push(enqueue_tx),.pop(take_tx),
        .data_i(tx_data_reg),.data_o(tx_head),.full(tx_full),.empty(tx_empty),.count(tx_count));
    uart_fifo #(.WIDTH(9),.DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk(clk),.reset_n(reset_n),.push(rx_done_i),.pop(consume_rx),
        .data_i({parity_error_i,rx_data_i[7:0]}),.data_o(rx_head),
        .full(rx_full_o),.empty(rx_empty),.count(rx_count));
    assign tx_data_o = {24'd0,tx_active};
    assign data_bit_num_o = cfg_reg[1:0];
    assign stop_bit_num_o = cfg_reg[2];
    assign parity_en_o = cfg_reg[3];
    assign parity_type_o = cfg_reg[4];
    assign rx_pending_o = !rx_empty;
    always @* begin
        error_o = !known_addr || (pwrite_i && ((paddr_i==REG_STT)||(paddr_i==REG_RX)||(paddr_i==REG_BAUD_ACTIVE)||(paddr_i==REG_INT_ST)));
        read_en_o=1; write_en_o=1; prdata_o=0;
        case (paddr_i)
            REG_TX: prdata_o={24'd0,tx_data_reg};
            // A queued frame must keep its original format until drained.
            REG_CFG: begin
                prdata_o={27'd0,cfg_reg};
                if (pstrb_i[0]) write_en_o=tx_done;
            end
            REG_CTRL: begin
                prdata_o={31'd0,start_tx_o};
                if (pstrb_i[0] && pwdata_i[0]) write_en_o=!tx_full || take_tx;
            end
            REG_STT: prdata_o={29'd0,parity_error,rx_done,tx_done};
            REG_RX: begin
                prdata_o={24'd0,(rx_empty ? rx_last : rx_head[7:0])};
                read_en_o=!rx_empty;
            end
            REG_BAUD_SHADOW: prdata_o={16'd0,baud_shadow};
            REG_BAUD_ACTIVE: prdata_o={16'd0,baud_div_o};
            REG_BAUD_CTRL: begin
                prdata_o[0]=!baud_safe;
                prdata_o[1]=baud_rejected;
                prdata_o[3]=(baud_shadow!=baud_div_o);
            end
            REG_INT_EN: prdata_o={29'd0,int_enable};
            REG_INT_ST: prdata_o={29'd0,int_status};
            REG_FIFO: begin
                prdata_o[0]=tx_full; prdata_o[1]=tx_empty;
                prdata_o[2]=rx_full_o; prdata_o[3]=rx_empty;
                prdata_o[4]=rx_overrun;
                prdata_o[15:8]=tx_count; prdata_o[23:16]=rx_count;
            end
            default: begin end
        endcase
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_data_reg<=0; tx_active<=0; rx_last<=0; cfg_reg<=0;
            tx_state<=IDLE; start_tx_o<=0; rx_overrun<=0;
            baud_shadow<=DEFAULT_DIV[15:0]; baud_div_o<=DEFAULT_DIV[15:0];
            baud_rejected<=0; int_enable<=0;
        end else begin
            case (tx_state)
                IDLE: if (take_tx) begin
                    tx_active<=tx_head; start_tx_o<=1; tx_state<=WAIT_BUSY;
                end
                WAIT_BUSY: if (tx_busy_i) begin
                    start_tx_o<=0; tx_state<=RUN;
                end
                RUN: if (tx_done_i) tx_state<=IDLE;
                default: begin tx_state<=IDLE; start_tx_o<=0; end
            endcase
            if (write_commit && paddr_i==REG_BAUD_SHADOW) begin
                if (pstrb_i[0]) baud_shadow[7:0]<=pwdata_i[7:0];
                if (pstrb_i[1]) baud_shadow[15:8]<=pwdata_i[15:8];
            end
            if (write_commit && pstrb_i[0]) begin
                case (paddr_i)
                    REG_TX: tx_data_reg<=pwdata_i[7:0];
                    REG_CFG: cfg_reg<=pwdata_i[4:0];
                    REG_INT_EN: int_enable<=pwdata_i[2:0];
                    REG_BAUD_CTRL: if (pwdata_i[1]) baud_rejected<=0;
                    REG_FIFO: if (pwdata_i[4]) rx_overrun<=0;
                    default: begin end
                endcase
            end
            if (apply_request) begin
                if (baud_apply_o) begin baud_div_o<=baud_shadow; baud_rejected<=0; end
                else baud_rejected<=1;
            end
            if (consume_rx) rx_last<=rx_head[7:0];
            // New overflow wins over a simultaneous software acknowledgement.
            if (rx_done_i && rx_full_o && !consume_rx) rx_overrun<=1;
        end
    end
endmodule
