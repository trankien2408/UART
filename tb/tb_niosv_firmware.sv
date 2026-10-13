`timescale 1ns/1ps
// Full generated SoC, including the actual Nios V model and compiled C ELF/HEX.
module tb_niosv_firmware;
    reg CLOCK_50=0; always #10 CLOCK_50=~CLOCK_50;
    reg KEY0=0, UART_RX=1;
    wire UART_CTS_N=1; // disconnected CTS is ignored in default 2-wire mode
    wire UART_TX, UART_RTS_N;
    wire [1:0] LEDG;
    de2_115_uart_top dut(.*);
    localparam integer BIT_NS=8681; // independent 115200-baud host clock
    integer echoed=0;
    integer instruction_responses=0, data_commands=0;
    reg [31:0] last_instruction_address=0, last_instruction=0, last_data_address=0;
    reg ready_seen=0;
    // Read-only retirement trace exported by the generated hart wrapper.
    // Keep the last 64 instructions to identify the FIRST exception before
    // the default HAL handler's ebreak causes recursive traps.
    wire retire_valid = dut.soc.cpu.hart.rvfi_valid;
    wire [31:0] retire_pc = dut.soc.cpu.hart.rvfi_pc_rdata;
    wire [31:0] retire_insn = dut.soc.cpu.hart.rvfi_insn;
    wire [31:0] retire_value = dut.soc.cpu.hart.rvfi_rd_wdata;
    reg [31:0] trace_pc[0:63], trace_insn[0:63];
    reg [31:0] first_cause=0, first_epc=0;
    integer trace_count=0;
    reg cause_seen=0, epc_seen=0;
    always @(posedge CLOCK_50) begin
        if(!KEY0) begin
            trace_count=0;
            cause_seen=0;
            epc_seen=0;
        end else if(retire_valid===1'b1) begin
            trace_pc[trace_count%64]=retire_pc;
            trace_insn[trace_count%64]=retire_insn;
            trace_count=trace_count+1;
            // CSRRS rd, csr, x0: the three CSR reads in the HAL trap vector.
            if(retire_insn[19:0] == 20'h02573 && retire_insn[31:20] == 12'h342) begin
                first_cause=retire_value;
                cause_seen=1;
                $display("UART_SIM: first trap mcause=%h", first_cause);
                for(integer j=(trace_count>64 ? trace_count-64 : 0);j<trace_count;j++)
                    $display("UART_SIM: trace pc=%h insn=%h",trace_pc[j%64],trace_insn[j%64]);
            end
            if(cause_seen && retire_insn == 32'h341025f3) begin
                first_epc=retire_value;
                epc_seen=1;
            end
            if(cause_seen && epc_seen && retire_insn == 32'h34302673)
                $fatal(1,"UART_SIM: first CPU exception mcause=%h mepc=%h mtval=%h",first_cause,first_epc,retire_value);
        end
    end
    // Observe public SoC bus signals; do not force CPU internals or skip boot.
    always @(posedge CLOCK_50) begin
        if(dut.soc.cpu_instruction_manager_read && !dut.soc.cpu_instruction_manager_waitrequest)
            last_instruction_address <= dut.soc.cpu_instruction_manager_address;
        if(dut.soc.cpu_instruction_manager_readdatavalid) begin
            instruction_responses <= instruction_responses+1;
            last_instruction <= dut.soc.cpu_instruction_manager_readdata;
        end
        if((dut.soc.cpu_data_manager_read || dut.soc.cpu_data_manager_write) &&
           !dut.soc.cpu_data_manager_waitrequest) begin
            data_commands <= data_commands+1;
            last_data_address <= dut.soc.cpu_data_manager_address;
        end
        if(LEDG[0]===1) ready_seen <= 1;
    end
    initial begin
        forever begin
            #1000000;
            $display("UART_SIM: t=%0t LED=%b reset_n=%b dbg_reset=%b ifetch_addr=%h instruction=%h fetch_responses=%0d data_addr=%h data_commands=%0d echoes=%0d",
                $time,LEDG,dut.soc.reset_reset_n,dut.soc.cpu_dbg_reset_out_reset,
                last_instruction_address,last_instruction,instruction_responses,
                last_data_address,data_commands,echoed);
        end
    end
    initial begin
        #5000000;
        if(!ready_seen) $fatal(1,"UART_SIM: boot watchdog: firmware READY absent after 5 ms; inspect bus progress above");
    end
    task send_byte(input [7:0] value);
        begin
            UART_RX=0; #BIT_NS;
            for(integer i=0;i<8;i++) begin UART_RX=value[i]; #BIT_NS; end
            UART_RX=1; #BIT_NS;
        end
    endtask
    task expect_byte(input [7:0] expected);
        reg [7:0] actual;
        begin
            @(negedge UART_TX);
            #(BIT_NS/2);
            if(UART_TX!==0) $fatal(1,"TX start glitch");
            for(integer i=0;i<8;i++) begin #BIT_NS; actual[i]=UART_TX; end
            #BIT_NS;
            if(UART_TX!==1 || actual!==expected)
                $fatal(1,"firmware echo: expected %h got %h stop=%b",expected,actual,UART_TX);
            #(BIT_NS/2);
            echoed++;
        end
    endtask
    task echo_one(input [7:0] value);
        fork send_byte(value); expect_byte(value); join
    endtask
    always @(posedge LEDG[1]) if(KEY0) $fatal(1,"Firmware reported UART/system-ID failure");
    initial begin
        repeat(10) @(negedge CLOCK_50); KEY0=1;
        $display("UART_SIM: board reset released at %0t",$time);
        wait(LEDG[0]===1);
        $display("Nios V firmware echo READY at %0t",$time);
        repeat(100) @(negedge CLOCK_50);
        for(integer i=0;i<32;i++) begin
            echo_one((i*37)&255);
            if((i%8)==7) $display("UART_SIM: verified %0d/32 UART echo bytes",i+1);
        end
        // KEY0 restarts the same image in on-chip RAM; RAM data is retained.
        KEY0=0; repeat(10) @(negedge CLOCK_50);
        if(LEDG!==0) $fatal(1,"board reset did not clear status LEDs");
        KEY0=1; wait(LEDG[0]===1);
        $display("UART_SIM: firmware READY after second reset at %0t",$time);
        repeat(100) @(negedge CLOCK_50);
        echo_one(8'h5a);
        $display("PASS tb_niosv_firmware: real Nios V CPU, C boot twice, external echoes=%0d",echoed);
        $finish;
    end
    initial begin #25000000; $fatal(1,"UART_SIM: full SoC simulation watchdog after 25 ms"); end
endmodule
