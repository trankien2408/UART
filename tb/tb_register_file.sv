`timescale 1ns/1ps
module tb_register_file;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0, access_i=0, pwrite_i=0;
    reg [3:0] pstrb_i=0;
    reg [11:0] paddr_i=0;
    reg [31:0] pwdata_i=0, rx_data_i=0;
    reg tx_busy_i=0, tx_done_i=0, rx_done_i=0, parity_error_i=0;
    wire read_en_o,write_en_o,error_o,start_tx_o,rx_pending_o;
    wire [31:0] prdata_o,tx_data_o;
    wire [1:0] data_bit_num_o;
    wire stop_bit_num_o,parity_en_o,parity_type_o;
    integer checks=0;
    register_file dut (.*);
    task automatic check(input bit pass,input string msg);
        checks++;
        if (!pass) $fatal(1,"register_file t=%0t: %s",$time,msg);
    endtask
    task automatic select_read(input [11:0] addr,input [31:0] expected);
        @(negedge clk); access_i=0; pwrite_i=0; paddr_i=addr;
        #1; check(prdata_o===expected,$sformatf("read %h expected %h got %h",addr,expected,prdata_o));
    endtask
    initial begin
        repeat (3) @(negedge clk); reset_n=1;
        select_read(12'hc,1);
        // The decoder seeing a valid write address is not itself a transaction.
        @(negedge clk); pwrite_i=1;paddr_i=0;pwdata_i=8'hab;pstrb_i=15;
        repeat (4) @(negedge clk);
        check(tx_data_o===0,"no write without access qualifier");
        access_i=1;
        @(negedge clk);access_i=0;
        check(tx_data_o===32'hab,"TX data committed once");
        paddr_i=8;pwdata_i=1;access_i=1;
        @(negedge clk);access_i=0;
        check(start_tx_o===1,"START held pending");
        select_read(12'hc,0);
        repeat (4) @(negedge clk);
        check(start_tx_o===1,"pending survives CTS wait");
        pwrite_i=1;paddr_i=0;pstrb_i=15;#1;
        check(write_en_o===0,"payload write waits while pending");
        pstrb_i=14;#1;check(write_en_o===1,"masked payload write does not wait");
        tx_busy_i=1;
        @(negedge clk);tx_busy_i=0;
        check(start_tx_o===0,"START clears when TX accepts");
        tx_done_i=1;
        @(negedge clk);tx_done_i=0;
        select_read(12'hc,1);
        // Completion is converted from a pulse into sticky RX status/data.
        @(negedge clk);rx_done_i=1;rx_data_i=32'h123400a5;parity_error_i=1;
        @(negedge clk);rx_done_i=0;parity_error_i=0;
        select_read(12'hc,7);select_read(12'h10,32'ha5);
        check(rx_pending_o===1,"read preview without access must not acknowledge RX");
        @(negedge clk);rx_done_i=1;rx_data_i=32'h5a;
        @(negedge clk);rx_done_i=0;
        select_read(12'h10,32'ha5);select_read(12'hc,7);
        // Exact same edge: CPU consumes old byte and receiver finishes a new one.
        @(negedge clk);paddr_i=12'h10;pwrite_i=0;access_i=1;
        rx_done_i=1;rx_data_i=32'h3c;parity_error_i=0;
        #1;check(prdata_o===32'ha5,"CPU sees old byte on simultaneous replacement");
        @(negedge clk);access_i=0;rx_done_i=0;
        select_read(12'hc,3);select_read(12'h10,32'h3c);
        @(negedge clk);access_i=1;
        @(negedge clk);access_i=0;
        select_read(12'hc,1);
        select_read(12'h10,32'h3c);
        check(read_en_o===0,"empty RX blocks but retains last data");
        // Empty read waiting on the completion cycle must not consume a byte
        // before the master has seen PREADY high on a clock edge.
        @(negedge clk);access_i=1;rx_done_i=1;rx_data_i=32'h81;
        #1;check(read_en_o===0,"not ready before RX completion edge");
        @(negedge clk);rx_done_i=0;
        #1;check(read_en_o===1 && prdata_o===32'h81,"ready with fresh byte");
        @(negedge clk);access_i=0;
        select_read(12'hc,1);
        // Invalid and RO writes cannot mutate either data or status.
        @(negedge clk);access_i=1;pwrite_i=1;paddr_i=12'hc;pwdata_i=0;pstrb_i=15;
        #1;check(error_o===1,"RO write error");
        @(negedge clk);access_i=0;
        select_read(12'hc,1);
        #3;reset_n=0;#1;
        check(start_tx_o===0 && rx_pending_o===0 && tx_data_o===0,"asynchronous reset");
        $display("PASS tb_register_file checks=%0d",checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"register file watchdog"); end
endmodule
