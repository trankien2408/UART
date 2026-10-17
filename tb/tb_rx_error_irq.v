`timescale 1ns/1ps
// Independent serial model plus APB BFM. Tests runtime configuration and level IRQs.
module tb_rx_error_irq;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,psel=0,penable=0,pwrite=0;
    reg [3:0] pstrb=0;
    reg [11:0] paddr=0;
    reg [31:0] pwdata=0;
    wire pready,pslverr;
    wire [31:0] prdata;
    reg rx=1,cts_n=0;
    wire tx,rts_n,irq;
    apb_uart dut(.clk(clk),.pclk(clk),.reset_n(reset_n),.presetn(reset_n),
        .psel(psel),.penable(penable),.pwrite(pwrite),.pstrb(pstrb),.paddr(paddr),.pwdata(pwdata),
        .pready(pready),.pslverr(pslverr),.prdata(prdata),.rx(rx),.cts_n(cts_n),.tx(tx),.rts_n(rts_n),.irq(irq));
    integer checks=0;
    reg [31:0] data;
    task check(input bit ok,input string msg);
        checks++;if(!ok)$fatal(1,"%s t=%0t",msg,$time);
    endtask
    task bus(input bit wr,input [11:0] addr,input [31:0] value,input [3:0] strb,output [31:0] answer,input bit expect_error=0);
        @(negedge clk);psel=1;penable=0;pwrite=wr;paddr=addr;pwdata=value;pstrb=strb;
        @(negedge clk);penable=1;
        begin: wait_ready
            for(integer n=0;n<100;n++) begin
                @(posedge clk);
                if(pready) begin answer=prdata;check(pslverr===expect_error,"APB error response");disable wait_ready;end
            end
            $fatal(1,"bus stall at %h",addr);
        end
        @(negedge clk);psel=0;penable=0;
    endtask
    task wr(input [11:0] a,input [31:0] v);
        reg[31:0] unused;bus(1,a,v,15,unused);
    endtask
    task rd(input [11:0] a,input [31:0] expected);
        bus(0,a,0,0,data);check(data===expected,$sformatf("read %h expected %h got %h",a,expected,data));
    endtask
    task apply_div(input integer div);
        wr('h18,div);wr('h20,6);rd('h1c,div);rd('h20,1); // quiet counter restarted, temporarily busy
    endtask
    task send_rx(input [7:0] value,input integer div,input bit bad_parity,input bit parity);
        rx=0;#(div*16*20);
        for(integer j=0;j<8;j++)begin rx=value[j];#(div*16*20);end
        if(parity)begin rx=(^value)^bad_parity;#(div*16*20);end
        rx=1;#(div*16*20);
    endtask
    task expect_tx(input [7:0] value,input integer div);
        @(negedge tx);#(div*8*20);check(tx==0,"TX start");
        for(integer j=0;j<8;j++)begin #(div*16*20);check(tx===value[j],"TX data at selected baud");end
        #(div*16*20);check(tx==1,"TX stop");
    endtask
    task wait_idle;
        repeat(20)begin
            bus(0,'hc,0,0,data);if(data[0])begin #(500*16*20*2);disable wait_idle;end
            #10000;
        end
        $fatal(1,"TX failed to drain");
    endtask
    integer peer_errors=0;
    wire peer_tick_tx,peer_tick_rx,peer_done,peer_parity,peer_error,peer_idle,peer_rts;
    wire [7:0] peer_data;
    baud_rate_gen peer_baud(.clk(clk),.rst_n(reset_n),.divider_i(16'd27),.reload_i(1'b0),
        .tick_tx(peer_tick_tx),.tick_rx(peer_tick_rx));
    // Model a remote UART fixed at ~115200 while the FPGA changes baud.
    rx_topmodule peer(.clk(clk),.reset_n(reset_n),.tick_rx(peer_tick_rx),.rx(tx),
        .data_bit_num_i(2'd3),.stop_bit_num_i(2'd0),.parity_en_i(1'b0),.parity_type_i(1'b0),
        .rx_data_o(peer_data),.rx_done_o(peer_done),.parity_error_o(peer_parity),
        .frame_error_o(peer_error),.baud_idle_o(peer_idle),.rts_n(peer_rts));
    always @(posedge clk) if(reset_n && peer_error) peer_errors<=peer_errors+1;
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        wr(4,3);wr('h24,8);rd('h28,2);check(!irq,"no framing IRQ after reset");
        send_rx(8'h41,27,0,0);rd('h10,8'h41);rd('h28,2);
        // A valid start + data + LOW stop must be dropped but produce an IRQ.
        rx=0;#(27*16*20);
        for(integer j=0;j<8;j++)begin rx=8'ha5>>j;#(27*16*20);end
        rx=0;#(27*16*20);rx=1;#(27*16*20*2);
        rd('h28,10);check(irq,"bad stop produces framing IRQ without a byte");
        bus(0,'h14,0,0,data);check(data[5] && data[3],"framing sticky flag and empty RX FIFO");
        bus(1,'h14,32,14,data);check(irq,"upper byte strobes cannot clear framing flag");
        wr('h24,0);check(!irq,"pending error respects interrupt mask");
        wr('h24,8);check(irq,"unmasking pending error raises IRQ");
        wr('h14,32);rd('h28,2);check(!irq,"W1C acknowledges framing IRQ");
        // RX direction: remote transmitter is much slower than FPGA receiver.
        send_rx(8'h00,326,0,0);#(27*16*20*2);
        bus(0,'h28,0,0,data);check(data[3] && irq,"baud mismatch on FPGA RX is observable");
        wr('h14,32);
        // Reset to isolate TX direction, drain all earlier decoded bytes.
        @(negedge clk);reset_n=0;repeat(3)@(negedge clk);reset_n=1;
        wr(4,3);#(27*16*20*3);apply_div(326);#(326*16*20*2);
        // FPGA transmits at 9600; peer stays at 115200 and flags framing errors.
        wr(0,0);wr(8,1);#(326*16*20*12);
        check(peer_errors>0,"baud mismatch on remote RX produces framing errors");
        // Recover FPGA to 115200 and verify a valid byte is accepted again.
        apply_div(27);#(27*16*20*2);wr('h24,8);
        send_rx(8'h5a,27,0,0);rd('h10,8'h5a);check(!irq,"matching baud recovers RX");
        #3;reset_n=0;#1;check(!irq,"reset clears framing IRQ");
        $display("PASS tb_rx_error_irq checks=%0d: bad stop, W1C/strobes/mask, both baud-mismatch directions, reset/recovery; peer_errors=%0d",checks,peer_errors);
        $finish;
    end
    initial begin #20000000;$fatal(1,"RX error watchdog");end
endmodule
