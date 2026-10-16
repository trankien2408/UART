`timescale 1ns/1ps
// Independent serial model plus APB BFM. Tests runtime configuration and level IRQs.
module tb_baud_irq;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,psel=0,penable=0,pwrite=0;
    reg [3:0] pstrb=0;
    reg [11:0] paddr=0;
    reg [31:0] pwdata=0;
    wire pready,pslverr;
    wire [31:0] prdata;
    reg rx=1,cts_n=0;
    wire tx,rts_n,irq;
    dti_uart dut(.clk(clk),.pclk(clk),.reset_n(reset_n),.presetn(reset_n),
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
    initial begin
        repeat(4)@(negedge clk);reset_n=1;
        rd('h1c,27);rd('h24,0);rd('h28,2);
        bus(1,'h1c,99,15,data,1);bus(1,'h28,99,15,data,1);
        bus(0,'h2c,0,0,data,1);bus(0,'h19,0,0,data,1);
        bus(1,'h24,7,14,data);rd('h24,0);
        bus(1,'h20,4,14,data);rd('h1c,27);check(!irq,"masked reset IRQ");
        wr('h24,2);#1;check(irq,"idle TX_DONE level IRQ");
        wr('h24,0);check(!irq,"mask lowers IRQ");
        #(27*16*20*2);rd('h20,0);
        // Byte lanes merge into shadow; active remains unchanged until APPLY.
        bus(1,'h18,'h1200,2,data);bus(1,'h18,'h34,1,data);rd('h18,'h1234);rd('h1c,27);
        wr('h18,0);wr('h20,6);rd('h1c,27);rd('h20,10);
        wr('h20,2);rd('h20,8);
        // Wire traffic across runtime baud changes (including pointer wrap).
        for(integer d=0;d<4;d++)begin
            case(d)0:data=326;1:data=54;2:data=27;3:data=163;endcase
            begin: format_test
                integer div;div=data;
                apply_div(div);#(div*16*20*2);wr(4,3);wr('h24,1);
                fork
                    send_rx(8'ha5,div,0,0);
                    begin wr(0,8'h68);wr(8,1);end
                    expect_tx(8'h68,div);
                join
                check(irq,"RX interrupt from wire");rd('h10,8'ha5);#1;check(!irq,"pop lowers IRQ");
                wait_idle();
            end
        end
        // TX pending CTS must reject APPLY immediately, preserve original baud.
        cts_n=1;repeat(5)@(negedge clk);wr(0,8'h77);wr(8,1);
        wr('h18,27);wr('h20,6);rd('h1c,163);rd('h20,11);
        fork expect_tx(8'h77,163);begin cts_n=0;end join
        wait_idle();apply_div(27);#(27*16*20*2);
        // A start edge arriving during the APPLY bus transaction wins: reject.
        wr('h18,54);
        fork
            send_rx(8'h5c,27,0,0);
            begin wr('h20,6);rd('h1c,27);end
        join
        rd('h10,8'h5c);#(27*16*20*2);
        // Reject while RX is receiving and preserve its original frame timing.
        wr('h18,54);
        fork
            send_rx(8'h39,27,0,0);
            begin #(27*16*20*3);wr('h20,6);rd('h1c,27);end
        join
        rd('h10,8'h39);rd('h20,11); // dirty + rejected
        #(27*16*20*2);apply_div(54);#(54*16*20*2);
        // Per-byte parity and overrun sources, combined masks.
        wr(4,27);wr('h24,5);
        for(integer k=0;k<17;k++)send_rx(k,54,k%2,1);
        rd('h28,7);check(irq,"RX and overrun assert IRQ");
        wr('h24,4);check(irq,"overrun independent of RX mask");
        wr('h14,16);#1;check(!irq,"W1C clears overrun IRQ while RX masked");
        wr('h24,1);check(irq,"unmask pending RX");
        for(integer k=0;k<16;k++)begin rd('hc,3+4*(k%2));rd('h10,k);end
        check(!irq,"drained all RX");
        wr('h24,2);check(irq,"TX idle enabled");
        #3;reset_n=0;#1;check(!irq && tx,"reset masks IRQ and resets output");
        @(negedge clk);reset_n=1;rd('h1c,27);rd('h24,0);
        $display("PASS tb_baud_irq checks=%0d dynamic wire baud, shadow/apply, CTS/RX rejection, IRQ masks/parity/overrun/reset",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"watchdog");end
endmodule
