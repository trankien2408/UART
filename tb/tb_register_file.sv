`timescale 1ns/1ps
module tb_register_file;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0, access_i=0, pwrite_i=0;
    reg [3:0] pstrb_i=0;
    reg [11:0] paddr_i=0;
    reg [31:0] pwdata_i=0, rx_data_i=0;
    reg tx_busy_i=0, tx_done_i=0, rx_done_i=0, parity_error_i=0;
    wire read_en_o,write_en_o,error_o,start_tx_o,rx_pending_o,rx_full_o;
    wire [31:0] prdata_o,tx_data_o;
    wire [1:0] data_bit_num_o;
    wire stop_bit_num_o,parity_en_o,parity_type_o;
    integer checks=0;
    register_file #(.FIFO_DEPTH(4)) dut (.*);
    task automatic check(input bit pass,input string msg);
        checks++;
        if (!pass) $fatal(1,"register_file t=%0t: %s",$time,msg);
    endtask
    task automatic wr(input [11:0] a,input [31:0] d);
        @(negedge clk); access_i=1;pwrite_i=1;pstrb_i=15;paddr_i=a;pwdata_i=d;
        #1;check(write_en_o && !error_o,"write ready");
        @(negedge clk);access_i=0;
    endtask
    task automatic rd(input [11:0] a,input [31:0] d,input bit consume);
        @(negedge clk);access_i=consume;pwrite_i=0;paddr_i=a;
        #1;check(prdata_o===d && read_en_o && !error_o,$sformatf("read %h expected %h got %h",a,d,prdata_o));
        @(negedge clk);access_i=0;
    endtask
    task automatic receive_byte(input [7:0] d,input bit bad);
        @(negedge clk);rx_data_i=d;parity_error_i=bad;rx_done_i=1;
        @(negedge clk);rx_done_i=0;
    endtask
    task automatic transmit_byte(input [7:0] d);
        wait(start_tx_o); #1;check(tx_data_o===d,"queued TX order and snapshot");
        @(negedge clk);tx_busy_i=1;
        @(negedge clk);check(!start_tx_o,"start acknowledged");
        repeat(3) @(negedge clk);
        tx_done_i=1;
        @(negedge clk);tx_done_i=0;tx_busy_i=0;
        @(negedge clk);
    endtask
    initial begin
        repeat(3) @(negedge clk);reset_n=1;
        rd(12'hc,1,0);rd(12'h14,10,0);
        // Staging only: neither an address preview nor a data write starts TX.
        @(negedge clk);pwrite_i=1;paddr_i=0;pwdata_i=99;pstrb_i=15;
        repeat(3) @(negedge clk);rd(0,0,0);
        for(integer i=0;i<5;i++) begin wr(0,8'h40+i);wr(8,1);end
        rd(12'h14,32'h409,0); // four queued + one active waiting on CTS
        @(negedge clk);paddr_i=8;pwrite_i=1;pwdata_i=1;
        #1;check(!write_en_o,"full TX backpressure");
        pstrb_i=14;#1;check(write_en_o,"masked START does not block");
        paddr_i=4;pstrb_i=15;#1;check(!write_en_o,"format held until drained");
        for(integer i=0;i<5;i++) transmit_byte(8'h40+i);
        rd(12'hc,1,0);
        // Wrap both FIFO pointers repeatedly; parity belongs to the head byte.
        for(integer round=0;round<12;round++) begin
            for(integer i=0;i<4;i++) receive_byte(round*4+i,i%2);
            check(rx_full_o,"RX full");
            receive_byte(8'hee,0); // overflow drops newest and preserves old bytes
            rd(12'h14,32'h40016,0);
            for(integer i=0;i<4;i++) begin
                rd(12'hc,3+4*(i%2),0);rd(12'h10,round*4+i,1);
            end
            wr(12'h14,16);rd(12'h14,10,0);
        end
        // Simultaneous full read/push retains count and accepts replacement.
        for(integer i=0;i<4;i++) receive_byte(i,0);
        @(negedge clk);paddr_i=12'h10;pwrite_i=0;access_i=1;rx_done_i=1;rx_data_i=4;
        #1;check(prdata_o==0 && read_en_o,"simultaneous read sees old head");
        @(negedge clk);access_i=0;rx_done_i=0;
        rd(12'h14,32'h40006,0);
        for(integer i=1;i<=4;i++) rd(12'h10,i,1);
        // Empty blocking read: arrival isn't consumed before ready is visible.
        @(negedge clk);access_i=1;paddr_i=12'h10;pwrite_i=0;rx_done_i=1;rx_data_i=8'h81;
        #1;check(!read_en_o,"empty read stalls");
        @(negedge clk);rx_done_i=0;#1;check(read_en_o && prdata_o==8'h81,"arrival ready");
        @(negedge clk);access_i=0;rd(12'hc,1,0);
        wr(0,8'hab);wr(8,1);receive_byte(99,1);
        #3;reset_n=0;#1;check(!start_tx_o && !rx_pending_o && tx_data_o==0,"reset flushes active and FIFOs");
        @(negedge clk);reset_n=1;rd(12'h14,10,0);rd(12'hc,1,0);
        $display("PASS tb_register_file checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
