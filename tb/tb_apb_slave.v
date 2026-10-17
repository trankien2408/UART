`timescale 1ns/1ps
// Testbench Verilog-2005: kiem tra rieng module apb_slave, khong sua RTL.
// read_en_i / write_en_i la READY tu Register File, khong phai write strobe.
// Mot giao dich commit tai canh len co PSEL && PENABLE && PREADY.
module tb_apb_slave;
    reg pclk, presetn;
    reg psel, penable, pwrite;
    reg [3:0] pstrb;
    reg [11:0] paddr;
    reg [31:0] pwdata;
    reg read_en_i, write_en_i, error_i;
    reg [31:0] prdata_i;

    wire pready, pslverr, access_o, pwrite_o;
    wire [31:0] prdata, pwdata_o;
    wire [11:0] paddr_o;
    wire [3:0] pstrb_o;

    integer errors, checks, cases_run, cases_passed, errors_before;
    integer completions, error_completions, saved_completions;
    integer i;
    reg [3:0] test_mask;

    apb_slave dut (
        .pclk(pclk), .presetn(presetn),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .pstrb(pstrb), .paddr(paddr), .pwdata(pwdata),
        .pready(pready), .pslverr(pslverr), .prdata(prdata),
        .pwrite_o(pwrite_o), .pstrb_o(pstrb_o),
        .paddr_o(paddr_o), .pwdata_o(pwdata_o), .access_o(access_o),
        .read_en_i(read_en_i), .write_en_i(write_en_i),
        .error_i(error_i), .prdata_i(prdata_i)
    );

    // Clock 50 MHz, cung tan so voi he thong.
    initial pclk = 1'b0;
    always #10 pclk = ~pclk;

    // Dem o canh clock hoan tat, khong dem so chu ky access_o giu muc 1.
    always @(posedge pclk) begin
        if (presetn && psel && penable && pready) begin
            completions = completions + 1;
            if (pslverr) error_completions = error_completions + 1;
        end
    end

    // Chi xuat VCD khi chay vvp ... +DUMP.
    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_apb_slave.vcd");
            $dumpvars(0, tb_apb_slave);
        end
    end

    task check;
        input condition;
        input [8*140-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL TC%0d t=%0t: %0s", cases_run, $time, message);
            end
        end
    endtask

    task begin_case;
        input [8*100-1:0] name;
        begin
            cases_run = cases_run + 1;
            errors_before = errors;
            $display("RUN  TC%0d: %0s", cases_run, name);
        end
    endtask

    task end_case;
        begin
            if (errors == errors_before) begin
                cases_passed = cases_passed + 1;
                $display("PASS TC%0d", cases_run);
            end else $display("FAIL TC%0d", cases_run);
        end
    endtask

    // Bat dau SETUP, sau do ACCESS. Lay mau #1 sau canh clock de tranh NBA race.
    // Task tra ve khi DUT vua vao ACCESS, chua den canh hoan tat giao dich.
    task begin_access;
        input wr;
        input [11:0] address;
        input [31:0] data;
        input [3:0] strobe;
        begin
            @(negedge pclk);
            psel = 1'b1; penable = 1'b0;
            pwrite = wr; paddr = address; pwdata = data; pstrb = strobe;
            #1;
            check(!pready && !access_o && !pslverr, "SETUP must not complete");
            @(posedge pclk); #1;
            check(pwrite_o === wr && paddr_o === address &&
                  pwdata_o === data && pstrb_o === strobe,
                  "SETUP must capture direction/address/data/strobes");
            check(!access_o && !pready, "captured SETUP is not yet ACCESS");
            @(negedge pclk); penable = 1'b1;
            #1;
            check(!pready && !access_o, "first ACCESS cycle has mandatory wait");
            @(posedge pclk); #1;
            check(access_o, "ACCESS must become active after mandatory wait");
        end
    endtask

    task complete_access;
        input expect_error;
        integer count_before;
        integer err_before;
        begin
            count_before = completions;
            err_before = error_completions;
            check(pready, "transfer must be ready before completion edge");
            check(pslverr === expect_error, "PSLVERR must match expected response");
            @(posedge pclk); #1;
            check(completions == count_before + 1, "exactly one completion edge");
            check(error_completions == err_before + (expect_error ? 1 : 0),
                  "error completion counter");
            check(!pready && !access_o && !pslverr, "completion must return interface to inactive");
            check(prdata === 32'd0, "PRDATA must be zero outside read ACCESS");
        end
    endtask

    task idle_bus;
        begin
            @(negedge pclk);
            psel = 0; penable = 0; pwrite = 0; pstrb = 0;
            paddr = 0; pwdata = 0;
            read_en_i = 1; write_en_i = 1; error_i = 0;
            @(posedge pclk); #1;
            check(!pready && !access_o && !pslverr && prdata === 0,
                  "idle bus has no ready/access/error/read data");
        end
    endtask

    initial begin
        errors = 0; checks = 0; cases_run = 0; cases_passed = 0;
        completions = 0; error_completions = 0;
        presetn = 1;
        psel = 0; penable = 0; pwrite = 0;
        pstrb = 0; paddr = 0; pwdata = 0;
        read_en_i = 1; write_en_i = 1; error_i = 0; prdata_i = 0;

        // TC1: reset bat dong bo va hanh vi IDLE.
        begin_case("Asynchronous reset and idle outputs");
        #3; presetn = 0; #1;
        check(!access_o && !pready && !pslverr && prdata === 0, "reset gates bus outputs immediately");
        check({pwrite_o,pstrb_o,paddr_o,pwdata_o} === 49'd0,
              "reset clears all captured request fields");
        repeat (2) @(negedge pclk);
        presetn = 1;
        idle_bus;
        end_case;

        // TC2: ghi thong thuong, co mot wait cycle bat buoc.
        begin_case("Normal write and mandatory wait cycle");
        begin_access(1'b1, 12'h004, 32'h12345678, 4'hf);
        check(pready && !pslverr, "ready write completes without error");
        check(prdata === 0, "write must not expose read data");
        complete_access(0);
        idle_bus;
        end_case;

        // TC3: doc dung PRDATA; write_en_i khong duoc chan giao dich doc.
        begin_case("Normal read uses only read-side readiness");
        write_en_i = 0; prdata_i = 32'h89abcdef;
        begin_access(1'b0, 12'h010, 32'd0, 4'd0);
        check(pready && prdata === 32'h89abcdef, "read response matches register data");
        complete_access(0);
        idle_bus;
        end_case;

        // TC4: backpressure ghi; read_en_i=1 khong duoc ket thuc som.
        begin_case("Write stalls until write_en_i is asserted");
        write_en_i = 0; read_en_i = 1;
        begin_access(1'b1, 12'h008, 32'h00000001, 4'h1);
        saved_completions = completions;
        repeat (3) begin
            @(posedge pclk); #1;
            check(access_o && !pready && !pslverr, "write ACCESS stays active while blocked");
            check(completions == saved_completions, "no write commits during wait");
            check(paddr_o === 12'h008 && pwdata_o === 32'h00000001 && pstrb_o === 4'h1,
                  "captured write fields remain stable during wait");
        end
        @(negedge pclk); write_en_i = 1; #1;
        complete_access(0);
        idle_bus;
        end_case;

        // TC5: backpressure doc; du lieu duoc chuyen tu Register File khi san sang.
        begin_case("Read stalls until read_en_i is asserted");
        read_en_i = 0; write_en_i = 1; prdata_i = 32'h00000000;
        begin_access(1'b0, 12'h010, 0, 0);
        saved_completions = completions;
        repeat (3) begin
            @(posedge pclk); #1;
            check(access_o && !pready && !pslverr, "read ACCESS stays active while blocked");
            check(completions == saved_completions, "no read commits during wait");
        end
        @(negedge pclk); prdata_i = 32'h000000a5; read_en_i = 1; #1;
        check(prdata === 32'h000000a5, "read data must reflect ready register response");
        complete_access(0);
        idle_bus;
        end_case;

        // TC6: APB Slave chi chuyen tiep PSTRB, Register File xu ly byte enable.
        begin_case("Byte strobes: zero, one byte, alternating and full word");
        for (i = 0; i < 4; i = i + 1) begin
            case (i)
                0: test_mask = 4'h0;
                1: test_mask = 4'h1;
                2: test_mask = 4'ha;
                3: test_mask = 4'hf;
            endcase
            begin_access(1'b1, 12'h018, 32'hfeedcafe, test_mask);
            check(pstrb_o === test_mask && pwdata_o === 32'hfeedcafe,
                  "strobe forwarded unchanged; APB Slave must not mask write data");
            complete_access(0);
        end
        idle_bus;
        end_case;

        // TC7: loi Register File phai ket thuc ca doc/ghi du READY dang bang 0.
        begin_case("Read/write error responses override register backpressure");
        read_en_i = 0; write_en_i = 0;
        begin_access(1'b0, 12'h02c, 0, 0);
        check(!pready && !pslverr, "no error response before error_i");
        @(negedge pclk); error_i = 1; prdata_i = 32'hdeadbeef; #1;
        check(pready && pslverr && prdata === 0, "error completes read and suppresses PRDATA");
        complete_access(1);
        // error_i remains high: PSLVERR must still be gated outside ACCESS.
        check(!pslverr, "PSLVERR only asserted with PREADY");
        begin_access(1'b1, 12'h00c, 32'h11223344, 4'hf);
        check(pready && pslverr, "error completes write despite write_en_i=0");
        complete_access(1);
        idle_bus;
        end_case;

        // TC8: giu PSEL=1, chen SETUP PENABLE=0 giua cac giao dich.
        begin_case("Back-to-back write/read/write with PSEL held high");
        saved_completions = completions;
        begin_access(1'b1, 12'h000, 32'h00000042, 4'h1);
        complete_access(0);
        check(psel, "PSEL held after first transfer");
        prdata_i = 32'h13579bdf;
        begin_access(1'b0, 12'h00c, 0, 0);
        check(psel && prdata === 32'h13579bdf, "second transfer has independent read response");
        complete_access(0);
        begin_access(1'b1, 12'h024, 32'h00000007, 4'h1);
        complete_access(0);
        check(completions == saved_completions + 3, "three transfers commit exactly three times");
        idle_bus;
        end_case;

        // TC9: reset giua ACCESS dang cho; huy giao dich cu, doc lai thanh cong.
        begin_case("Reset during stalled ACCESS and recovery");
        read_en_i = 0;
        begin_access(1'b0, 12'h010, 0, 0);
        saved_completions = completions;
        #3; presetn = 0; #1;
        check(!access_o && !pready && !pslverr && prdata === 0,
              "asynchronous reset immediately cancels stalled ACCESS");
        check({pwrite_o,pstrb_o,paddr_o,pwdata_o} === 49'd0,
              "reset during access clears captured request");
        @(negedge pclk);
        psel = 0; penable = 0; read_en_i = 1;
        repeat (2) @(negedge pclk);
        presetn = 1;
        @(posedge pclk); #1;
        check(completions == saved_completions, "reset transaction never commits later");
        prdata_i = 32'hcafebabe;
        begin_access(1'b0, 12'h000, 0, 0);
        check(prdata === 32'hcafebabe, "new transaction works after reset");
        complete_access(0);
        idle_bus;
        end_case;

        // TC10: huy SETUP va PENABLE khi khong duoc chon (kiem tra bao ve giao tiep).
        // Huy SETUP khong phai giao dich APB hop le; day la robustness test.
        begin_case("Unselected bus and canceled SETUP cannot create a completion");
        saved_completions = completions;
        @(negedge pclk);
        psel = 0; penable = 1; error_i = 1;
        repeat (2) begin
            @(posedge pclk); #1;
            check(!access_o && !pready && !pslverr, "unselected bus ignores PENABLE and error_i");
        end
        @(negedge pclk);
        psel = 1; penable = 0; error_i = 0;
        pwrite = 1; paddr = 12'h004; pwdata = 32'h11223344; pstrb = 4'hf;
        @(posedge pclk); #1;
        check(!access_o && !pready, "SETUP has no completion");
        @(negedge pclk); psel = 0; penable = 0;
        repeat (2) begin
            @(posedge pclk); #1;
            check(!access_o && !pready && !pslverr, "canceled SETUP must not access registers");
        end
        check(completions == saved_completions, "no phantom completion after canceled SETUP");
        prdata_i = 32'h55aa00ff;
        begin_access(1'b0, 12'h004, 0, 0);
        check(prdata === 32'h55aa00ff, "valid read works after canceled SETUP");
        complete_access(0);
        idle_bus;
        end_case;

        if (errors == 0 && cases_run == 10 && cases_passed == 10)
            $display("PASS tb_apb_slave: %0d/10 testcases, %0d checks, %0d completions, %0d error responses",
                     cases_passed, checks, completions, error_completions);
        else
            $display("FAIL tb_apb_slave: passed=%0d/10 errors=%0d checks=%0d",
                     cases_passed, errors, checks);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL tb_apb_slave: watchdog timeout");
        $finish;
    end
endmodule
