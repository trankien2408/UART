`timescale 1ns/1ps
module tb_dti_uart;
    parameter integer BAUDRATE = 115200;
    parameter integer SMOKE = 0;
    localparam integer CLK_FREQ = 50000000;
    localparam real BIT_NS = 1.0e9 / BAUDRATE;
    localparam integer TIMEOUT_CYCLES = (CLK_FREQ / BAUDRATE) * 40;
    localparam [11:0] TX = 12'h000, CFG = 12'h004, CTRL = 12'h008,
                     STT = 12'h00c, RX = 12'h010;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_n = 0, presetn = 0;
    reg psel = 0, penable = 0, pwrite = 0;
    reg [3:0] pstrb = 0;
    reg [11:0] paddr = 0;
    reg [31:0] pwdata = 0;
    wire pready, pslverr;
    wire [31:0] prdata;
    reg rx = 1, cts_n = 0;
    wire tx, rts_n;
    integer checks = 0, tx_frames = 0, rx_frames = 0, seed = 12345, rng, seed_state;
    integer last_wait;
    reg [31:0] result;
    bit error;
    dti_uart #(.CLK_FREQ(CLK_FREQ), .BAUDRATE(BAUDRATE)) dut (
        .clk(clk), .reset_n(reset_n), .pclk(clk), .presetn(presetn),
        .psel(psel), .penable(penable), .pwrite(pwrite), .pstrb(pstrb),
        .paddr(paddr), .pwdata(pwdata), .pready(pready), .pslverr(pslverr),
        .prdata(prdata), .rx(rx), .cts_n(cts_n), .tx(tx), .rts_n(rts_n)
    );
    task automatic check(input bit condition, input string message);
        checks++;
        if (!condition) $fatal(1, "CHECK FAILED t=%0t baud=%0d: %s", $time, BAUDRATE, message);
    endtask
    function automatic [31:0] config_word(input integer bits, stops, mode);
        // mode 0 = none, 1 = odd, 2 = even (as specified by dti_uart.pdf).
        config_word = (bits - 5) | ((stops - 1) << 2) |
                      ((mode != 0) << 3) | ((mode == 2) << 4);
    endfunction
    function automatic [7:0] masked(input [7:0] data, input integer bits);
        masked = data & ((1 << bits) - 1);
    endfunction
    task automatic reset_dut;
        @(negedge clk);
        reset_n = 0; presetn = 0;
        psel = 0; penable = 0; pwrite = 0; pstrb = 0;
        rx = 1; cts_n = 0;
        repeat (6) @(negedge clk);
        reset_n = 1; presetn = 1;
        repeat (6) @(negedge clk);
        check(tx === 1'b1, "TX idle after reset");
        check(rts_n === 1'b0, "RX ready after reset");
    endtask
    task automatic apb(input bit wr, input [11:0] address,
                       input [31:0] data, input [3:0] strobes,
                       output reg [31:0] rd, output bit err);
        integer cycles;
        @(negedge clk);
        psel = 1; penable = 0; pwrite = wr;
        paddr = address; pwdata = data; pstrb = wr ? strobes : 4'd0;
        #1;
        check(pready === 0 && pslverr === 0, "no response in APB SETUP");
        @(negedge clk); penable = 1;
        cycles = 0;
        do begin
            @(posedge clk);
            cycles++;
            if (cycles > TIMEOUT_CYCLES) $fatal(1, "APB timeout addr=%h", address);
        end while (pready !== 1'b1);
        rd = prdata; err = pslverr;
        // Reduction XOR propagates both X and Z, without relying on Icarus
        // $isunknown handling of a concatenation inside an automatic task.
        check((^{prdata, pslverr}) !== 1'bx,
              $sformatf("known APB response: addr=%h data=%h error=%b", address, prdata, pslverr));
        last_wait = cycles - 1;
        @(negedge clk);
        psel = 0; penable = 0; pwrite = 0; pstrb = 0;
    endtask
    task automatic write_reg(input [11:0] address, input [31:0] data);
        reg [31:0] rd; bit err;
        apb(1, address, data, 4'hf, rd, err);
        check(!err, $sformatf("write address %h", address));
    endtask
    task automatic read_reg(input [11:0] address, output reg [31:0] data);
        bit err;
        apb(0, address, 0, 0, data, err);
        check(!err, $sformatf("read address %h", address));
    endtask
    task automatic expect_reg(input [11:0] address, input [31:0] expected);
        reg [31:0] rd;
        read_reg(address, rd);
        check(rd === expected, $sformatf("addr %h expected %h got %h", address, expected, rd));
    endtask
    task automatic wait_tx_ready;
        reg [31:0] rd;
        integer count;
        count = 0;
        do begin
            read_reg(STT, rd);
            count++;
            if (count > TIMEOUT_CYCLES) $fatal(1, "TX ready timeout");
        end while (!rd[0]);
    endtask
    // Independent external transmitter. No access to DUT counters/ticks.
    task automatic send_rx(input [7:0] data, input integer bits, stops, mode,
                           input bit bad_parity, input integer bad_stop_mask,
                           input real bit_time);
        reg parity;
        parity = ^masked(data, bits);
        if (mode == 1) parity = ~parity;
        rx = 0; #(bit_time);
        for (integer j = 0; j < bits; j++) begin rx = data[j]; #(bit_time); end
        if (mode != 0) begin rx = parity ^ bad_parity; #(bit_time); end
        for (integer j = 0; j < stops; j++) begin
            rx = !((bad_stop_mask >> j) & 1); #(bit_time);
        end
        rx = 1;
        rx_frames++;
    endtask
    // Independent receiver samples actual TX pin at nominal baud bit centres.
    task automatic expect_tx(input [7:0] data, input integer bits, stops, mode);
        reg parity;
        @(negedge tx);
        #(BIT_NS / 2.0);
        check(tx === 0, "TX start bit");
        for (integer j = 0; j < bits; j++) begin
            #(BIT_NS);
            check(tx === data[j], $sformatf("TX bit %0d of %h", j, data));
        end
        parity = ^masked(data, bits);
        if (mode == 1) parity = ~parity;
        if (mode != 0) begin
            #(BIT_NS);
            check(tx === parity, "TX parity bit");
        end
        for (integer j = 0; j < stops; j++) begin
            #(BIT_NS); check(tx === 1, $sformatf("TX stop bit %0d", j));
            check(dut.u_registers.tx_done === 0, "TX done must not assert before stop-bit centre");
        end
        tx_frames++;
    endtask
    task automatic check_received(input [7:0] expected, input bit parity_bad);
        reg [31:0] rd;
        read_reg(STT, rd);
        check(rd[2:1] === {parity_bad, 1'b1}, "RX done/parity status");
        check(rts_n === 0, "RTS permits more bytes while FIFO has room");
        expect_reg(RX, {24'd0, expected});
        read_reg(STT, rd);
        check(rd[2:1] === 0, "RX read clears done and parity error");
        check(rts_n === 0, "RTS ready again after RX read");
    endtask
    task automatic duplex(input [7:0] out_byte, in_byte,
                           input integer bits, stops, mode, input real skew);
        write_reg(CFG, config_word(bits, stops, mode));
        write_reg(TX, out_byte);
        fork
            expect_tx(out_byte, bits, stops, mode);
            begin #137; send_rx(in_byte, bits, stops, mode, 0, 0, BIT_NS * skew); end
            write_reg(CTRL, 1);
        join
        wait_tx_ready();
        check_received(masked(in_byte, bits), 0);
        expect_reg(CTRL, 0);
    endtask
    // Keep PSEL high and insert only the required single SETUP cycle.
    task automatic back_to_back;
        @(negedge clk);
        psel = 1; penable = 0; pwrite = 1; pstrb = 15; paddr = CFG; pwdata = 3;
        @(negedge clk); penable = 1;
        do @(posedge clk); while (!pready);
        check(!pslverr, "first back-to-back write");
        @(negedge clk); penable = 0; paddr = TX; pwdata = 8'h69;
        @(negedge clk); penable = 1;
        do @(posedge clk); while (!pready);
        check(!pslverr, "second back-to-back write");
        @(negedge clk); penable = 0; pwrite = 0; pstrb = 0; paddr = TX;
        @(negedge clk); penable = 1;
        do @(posedge clk); while (!pready);
        check(!pslverr && prdata === 32'h69, "back-to-back read");
        @(negedge clk); psel = 0; penable = 0;
    endtask

    // Protocol response guard applies to every test, including wait states.
    always @(posedge clk) if (reset_n && presetn) begin
        if (pslverr && !(psel && penable && pready))
            $fatal(1, "PSLVERR outside completion cycle");
        if (!psel && pready) $fatal(1, "PREADY while not selected");
    end
    initial begin
        #(BIT_NS * 20000);
        $fatal(1, "Global watchdog timeout");
    end
    initial begin : tests
        integer bits, stops, mode, i, st;
        reg [7:0] patterns [0:7];
        reg [7:0] out_byte, in_byte;
        reg [31:0] cfg_expected, tx_expected;
        real skew;
        if ($value$plusargs("SEED=%d", seed)) begin end
        seed_state = seed;
        rng = $urandom(seed_state);
        patterns[0]=0; patterns[1]=8'hff; patterns[2]=8'ha5; patterns[3]=8'h5a;
        patterns[4]=8'h01; patterns[5]=8'h80; patterns[6]=8'h7e; patterns[7]=8'h81;
        $display("TEST baud=%0d smoke=%0d seed=%0d", BAUDRATE, SMOKE, seed);
        reset_dut();
        expect_reg(TX, 0); expect_reg(CFG, 0); expect_reg(CTRL, 0); expect_reg(STT, 1);
        if (SMOKE) begin
            for (i=0; i<4; i++) duplex(patterns[i+2], patterns[7-i], 5+i, 1+(i%2), i%3, 1.0);
            $display("PASS tb_dti_uart baud=%0d checks=%0d tx_frames=%0d rx_frames=%0d", BAUDRATE, checks, tx_frames, rx_frames);
            $finish;
        end
        $display("CASE register access, all byte strobes, reserved bits and errors");
        cfg_expected = 0; tx_expected = 0;
        for (st=0; st<16; st++) begin
            rng = $urandom;
            apb(1, CFG, rng, st[3:0], result, error); check(!error, "CFG strobe write");
            if (st & 1) cfg_expected = rng & 31;
            expect_reg(CFG, cfg_expected);
            rng = $urandom;
            apb(1, TX, rng, st[3:0], result, error); check(!error, "TX strobe write");
            if (st & 1) tx_expected = rng & 255;
            expect_reg(TX, tx_expected);
        end
        for (i=0; i<5; i++) begin
            for (st=1; st<4; st++) begin
                apb(1, i*4+st, 32'hffffffff, 15, result, error); check(error, "unaligned write error");
                apb(0, i*4+st, 0, 0, result, error); check(error && result===0, "unaligned read error");
            end
        end
        apb(0, 12'h02c, 0, 0, result, error); check(error, "unmapped read");
        apb(1, 12'h100, 32'hffffffff, 15, result, error); check(error, "upper address no alias");
        apb(0, 12'hffc, 0, 0, result, error); check(error, "last unmapped address");
        apb(1, STT, 0, 15, result, error); check(error, "STATUS is read-only");
        apb(1, RX, 1, 15, result, error); check(error, "RX is read-only");
        expect_reg(CFG, cfg_expected); expect_reg(TX, tx_expected); expect_reg(STT, 1);
        apb(1, CTRL, 1, 14, result, error); check(!error, "masked START");
        write_reg(CTRL, 32'hfffffffe); expect_reg(CTRL, 0); expect_reg(STT, 1);
        back_to_back();
        // Abort a SETUP before ACCESS: no data register may change.
        @(negedge clk); psel=1; penable=0; pwrite=1; paddr=TX; pwdata=32'hbad; pstrb=15;
        @(negedge clk); psel=0; pwrite=0; pstrb=0;
        repeat (2) @(negedge clk);
        expect_reg(TX, 32'h69);

        $display("CASE all 24 frame formats x 8 payload patterns, simultaneous TX/RX");
        for (bits=5; bits<=8; bits++)
            for (stops=1; stops<=2; stops++)
                for (mode=0; mode<=2; mode++)
                    for (i=0; i<8; i++) duplex(patterns[i], ~patterns[i], bits, stops, mode, 1.0);

        $display("CASE 64 seeded random duplex frames, asynchronous phase and +/-2%% RX baud skew");
        for (i=0; i<64; i++) begin
            bits=5+$urandom_range(0,3); stops=1+$urandom_range(0,1); mode=$urandom_range(0,2);
            out_byte=$urandom; in_byte=$urandom; skew=0.98+0.01*$urandom_range(0,4);
            #($urandom_range(1,300));
            duplex(out_byte,in_byte,bits,stops,mode,skew);
        end

        $display("CASE parity errors, false start, bad first/second stop, break and recovery");
        for (bits=5; bits<=8; bits++) for (mode=1; mode<=2; mode++) begin
            write_reg(CFG,config_word(bits,2,mode));
            send_rx(8'hd6,bits,2,mode,1,0,BIT_NS);
            check_received(masked(8'hd6,bits),1);
        end
        write_reg(CFG,3);
        rx=0; #(BIT_NS/4); rx=1; #(BIT_NS*2);
        expect_reg(STT,1); check(rts_n===0,"false-start recovery");
        for (st=1; st<=2; st++) begin
            write_reg(CFG,config_word(8,2,0));
            send_rx(8'ha5,8,2,0,0,st,BIT_NS); #(BIT_NS);
            expect_reg(STT,1);
        end
        rx=0; #(BIT_NS*14); rx=1; #(BIT_NS*2); expect_reg(STT,1);
        send_rx(8'hb7,8,2,0,0,0,BIT_NS); check_received(8'hb7,0);

        $display("CASE unread RX preservation and RTS, no gap between two frames");
        write_reg(CFG,3);
        send_rx(8'h11,8,1,0,0,0,BIT_NS);
        send_rx(8'h22,8,1,0,0,0,BIT_NS); // FIFO retains both bytes
        expect_reg(RX,32'h11); check_received(8'h22,0);
        fork
            begin
                send_rx(8'h33,8,1,0,0,0,BIT_NS*0.98);
                send_rx(8'hcc,8,1,0,0,0,BIT_NS*0.98);
            end
            begin
                // A blocking RX read is already waiting before each completion.
                expect_reg(RX,32'h33);
                expect_reg(RX,32'hcc);
            end
        join
        expect_reg(STT,1);

        $display("CASE CTS stall retains START, TX staging can change while busy");
        cts_n=1; repeat (5) @(negedge clk);
        write_reg(TX,8'h96); write_reg(CTRL,1);
        expect_reg(STT,0); expect_reg(CTRL,1);
        #(BIT_NS*2); check(tx===1,"CTS blocks TX start");
        fork
            expect_tx(8'h96,8,1,0);
            begin #(BIT_NS/3); cts_n=0; end
            begin
                write_reg(TX,8'h3c);
                check(last_wait<10,"staging write independent of active frame");
            end
        join
        expect_reg(CTRL,0);
        fork expect_tx(8'h3c,8,1,0); write_reg(CTRL,1); join
        wait_tx_ready(); #(BIT_NS*2); check(tx===1,"no duplicate START");

        $display("CASE START while busy queues, CTS change cannot truncate active TX");
        write_reg(TX,8'hc3);
        fork
            begin expect_tx(8'hc3,8,1,0); expect_tx(8'hc3,8,1,0); end
            begin
                write_reg(CTRL,1);
                #(BIT_NS*3);
                write_reg(CTRL,1);
                check(last_wait<10,"second START queues while transmitting");
            end
        join
        wait_tx_ready();
        write_reg(TX,8'h5a);
        fork
            expect_tx(8'h5a,8,1,0);
            begin write_reg(CTRL,1); #(BIT_NS*3); cts_n=1; end
        join
        wait_tx_ready();
        check(tx===1,"active frame completes despite CTS deassertion");
        cts_n=0; repeat(5) @(negedge clk);

        $display("CASE config changes during frame take effect only on next frame");
        write_reg(CFG,config_word(8,2,2)); write_reg(TX,8'h87);
        fork
            expect_tx(8'h87,8,2,2);
            send_rx(8'hf1,8,2,2,0,0,BIT_NS);
            begin write_reg(CTRL,1); #(BIT_NS*3); write_reg(CFG,0); end
        join
        wait_tx_ready(); check_received(8'hf1,0);
        duplex(8'h1b,8'h13,5,1,0,1.0);

        $display("CASE FIFO wire burst: CTS stall, full backpressure, ordered drain");
        write_reg(CFG,3); cts_n=1; repeat(5) @(negedge clk);
        for(integer k=0;k<17;k++) begin write_reg(TX,8'h50+k);write_reg(CTRL,1);end
        read_reg(12'h14,result);check(result[0] && result[15:8]==16,"16 queued plus one active");
        write_reg(TX,8'h61);
        fork
            begin for(integer k=0;k<18;k++) expect_tx(8'h50+k,8,1,0);end
            begin #(BIT_NS*2);cts_n=0;end
            begin write_reg(CTRL,1);check(last_wait>10,"full FIFO stalls START until room");end
        join
        wait_tx_ready();#(BIT_NS*2);check(tx===1,"burst no duplicate frame");
        $display("CASE RX FIFO wire burst: parity per byte, full RTS, overrun and wrap");
        write_reg(CFG,config_word(8,1,2));
        for(integer round=0;round<2;round++) begin
            for(integer k=0;k<17;k++) send_rx(k+round*32,8,1,2,k%2,0,BIT_NS);
            read_reg(12'h14,result);
            check(result[4] && result[2] && result[23:16]==16 && rts_n,"full RX and sticky overrun");
            for(integer k=0;k<16;k++) begin
                read_reg(STT,result);check(result[2:1]=={(k%2!=0),1'b1},"parity follows FIFO head");
                expect_reg(RX,k+round*32);
            end
            expect_reg(STT,1);check(!rts_n,"RTS resumes after drain");
            write_reg(12'h14,16);expect_reg(12'h14,10);
        end

        $display("CASE reset in TX, RX and stalled APB access");
        write_reg(CFG,3); write_reg(TX,8'h00); write_reg(CTRL,1);
        #(BIT_NS*3); #3; reset_n=0;
        #1; check(tx===1 && pready===0,"async reset aborts TX and bus");
        reset_dut(); expect_reg(STT,1);
        write_reg(CFG,3);
        rx=0; #(BIT_NS*3); #3; presetn=0; rx=1;
        #1; check(tx===1 && pready===0,"APB reset resets entire UART");
        reset_dut(); expect_reg(STT,1);
        @(negedge clk); psel=1; penable=0; pwrite=0; pstrb=0; paddr=RX;
        @(negedge clk); penable=1;
        repeat (10) begin @(posedge clk); check(pready===0,"empty RX read waits"); end
        #3; presetn=0;
        #1; check(pready===0 && pslverr===0,"reset cancels waiting APB");
        reset_dut(); expect_reg(STT,1);
        duplex(8'ha6,8'h59,8,1,0,1.0);
        $display("PASS tb_dti_uart baud=%0d checks=%0d tx_frames=%0d rx_frames=%0d", BAUDRATE,checks,tx_frames,rx_frames);
        $finish;
    end
endmodule
