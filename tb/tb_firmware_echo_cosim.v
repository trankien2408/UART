`timescale 1ns/1ps
// main.c + console.c + driver on host CPU; real Avalon/APB/UART RTL at 50 MHz.
module tb_firmware_echo_cosim;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0;
    reg [11:0] av_address=0;
    reg av_read=0, av_write=0;
    reg [31:0] av_writedata=0;
    reg [3:0] av_byteenable=0;
    wire av_waitrequest, av_readdatavalid, av_writeresponsevalid;
    wire [31:0] av_readdata;
    wire [1:0] av_response;
    wire cts_n=0;
    wire tx, rts_n;
    reg rx=1;
    wire irq;
    uart_avalon dut(.*);
    reg accepted=0, rvalid=0, wvalid=0;
    reg [31:0] rdata=0, cycles=0, control=0;
    reg [1:0] response=0;
    integer received=0;
    integer BIT_NS=8681;
    reg [31:0] baud_phase=0;
    reg [31:0] diagnostic_seen=0;
    reg allow_rx_error=0;
    always @(posedge clk) begin
        cycles<=cycles+1;
        accepted<=reset_n && (av_read || av_write) && !av_waitrequest;
        rvalid<=av_readdatavalid; wvalid<=av_writeresponsevalid;
        rdata<=av_readdata; response<=av_response;
    end
    always @(negedge clk) if(reset_n)
        $firmware_tick(av_address,av_read,av_write,av_writedata,av_byteenable,
                       accepted,rvalid,wvalid,rdata,response,cycles,control,irq,baud_phase,diagnostic_seen);
    always @(control) if(control[3] && !allow_rx_error) $fatal(1,"C echo application reported error");
    task send_byte(input [7:0] value);
        begin
            rx=0; #BIT_NS;
            for(integer i=0;i<8;i++) begin rx=value[i]; #BIT_NS; end
            rx=1; #BIT_NS;
        end
    endtask
    task expect_byte(input [7:0] expected);
        reg [7:0] actual;
        begin
            @(negedge tx); #(BIT_NS/2);
            if(tx!==0) $fatal(1,"TX start glitch");
            for(integer i=0;i<8;i++) begin #BIT_NS; actual[i]=tx; end
            #BIT_NS;
            if(tx!==1 || actual!==expected)
                $fatal(1,"echo expected %h got %h stop=%b",expected,actual,tx);
            // Re-arm at the stop-bit midpoint. RTL baud divider runs slightly
            // faster than the nominal host, so waiting a full frame misses
            // the next start edge during a back-to-back burst.
            received++;
        end
    endtask
    initial begin
        $firmware_start;
        repeat(5) @(posedge clk); #1; reset_n=1;
        wait(control[2]);
        // 8 lines, each 31 printable bytes plus LF. LF echoes as CRLF.
        for(integer i=0;i<256;i++) begin
            if ((i%32)==31) begin
                fork
                    send_byte(8'h0a);
                    begin expect_byte(8'h0d); expect_byte(8'h0a); end
                join
            end else begin
                fork send_byte(8'h61+(i%26)); expect_byte(8'h61+(i%26)); join
            end
        end
        // Continuous input burst; normalized newlines add one output byte.
        fork
            begin
                for(integer i=0;i<256;i++)
                    send_byte((i%32)==31 ? 8'h0a : 8'h61+(i%26));
            end
            begin
                for(integer i=0;i<256;i++) begin
                    if ((i%32)==31) begin expect_byte(8'h0d); expect_byte(8'h0a); end
                    else expect_byte(8'h61+(i%26));
                end
            end
        join
        repeat(12000) begin @(posedge clk); if(tx!==1) $fatal(1,"extra TX byte"); end
        // Real application parses the JTAG command and changes actual RTL baud.
        baud_phase=1;
        wait(dut.uart.u_registers.baud_div_o==326);BIT_NS=104167;
        #300000;
        for(integer i=0;i<5;i++)begin
            fork send_byte("h"+i);expect_byte("h"+i);join
        end
        fork send_byte(10);begin expect_byte(13);expect_byte(10);end join
        #300000;baud_phase=2;
        wait(dut.uart.u_registers.baud_div_o==27);BIT_NS=8681;
        #300000;
        fork send_byte("Z");expect_byte("Z");join
        fork send_byte(10);begin expect_byte(13);expect_byte(10);end join
        #300000;baud_phase=3;#300000;
        if(dut.uart.u_registers.baud_div_o!=27)$fatal(1,"unsupported baud must not change active divider");
        // Wrong-baud input has no Enter: the real ISR/main must still report it.
        allow_rx_error=1;BIT_NS=104167;send_byte(0);#500000;
        if(!diagnostic_seen)$fatal(1,"wrong-baud framing error did not reach JTAG");
        // A lost Enter must not prevent restoring baud using the JTAG command.
        baud_phase=4;#1000000;BIT_NS=8681;
        fork send_byte("K");expect_byte("K");join
        fork send_byte(10);begin expect_byte(13);expect_byte(10);end join
        $display("PASS firmware_echo_cosim: actual C app + UART RTL, %0d output bytes, line endings, burst, real IRQ, baud commands, wrong-baud framing diagnostic without Enter and recovery",received);
        $finish;
    end
    initial begin #100000000; $fatal(1,"echo co-simulation watchdog"); end
endmodule
