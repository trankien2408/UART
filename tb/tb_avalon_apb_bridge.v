`timescale 1ns/1ps
module tb_avalon_apb_bridge;
    reg clk=0; always #10 clk=~clk;
    reg reset_n=0;
    reg [11:0] av_address=0;
    reg av_read=0, av_write=0;
    reg [31:0] av_writedata=0;
    reg [3:0] av_byteenable=0;
    wire av_waitrequest, av_readdatavalid, av_writeresponsevalid;
    wire [31:0] av_readdata;
    wire [1:0] av_response;
    wire psel, penable, pwrite;
    wire [11:0] paddr;
    wire [31:0] pwdata;
    wire [3:0] pstrb;
    reg [3:0] waits=0;
    wire pready=psel && penable && waits==0;
    wire pslverr=pready && paddr[8];
    wire [31:0] prdata=32'ha5a50000 | paddr;
    avalon_apb_bridge dut(.*);
    reg [11:0] exp_addr[0:1023];
    reg [31:0] exp_data[0:1023];
    reg [3:0] exp_strb[0:1023];
    reg exp_write[0:1023];
    integer accepted=0, responses=0, commits=0, checks=0;
    integer seed=32'h12a4, i;
    reg [47:0] stable_fields;
    reg was_stalled=0;
    task check(input bit ok, input string message);
        begin checks++; if(!ok) $fatal(1,"%s at %0t",message,$time); end
    endtask
    always @(negedge clk) begin
        if (!reset_n) waits<=0;
        else if(psel && !penable) waits <= $random(seed) & 15;
        else if(psel && penable && waits!=0) waits <= waits-1;
    end
    always @(posedge clk) begin
        if (!reset_n) begin
            accepted=0; responses=0; commits=0; was_stalled=0;
        end else begin
            if ((av_read || av_write) && !av_waitrequest) begin
                exp_addr[accepted]=av_address;
                exp_write[accepted]=av_write;
                exp_data[accepted]=av_writedata;
                exp_strb[accepted]=av_write ? av_byteenable : 0;
                accepted++;
            end
            if (psel) begin
                check(commits < accepted,"APB must follow accepted Avalon command");
                check(paddr===exp_addr[commits] && pwrite===exp_write[commits],"APB command capture");
                check(pwdata===exp_data[commits] && pstrb===exp_strb[commits],"data and strobes");
            end
            if (was_stalled) check({paddr,pwdata,pstrb}===stable_fields && psel && penable,"APB stable through waits");
            was_stalled=psel && penable && !pready;
            stable_fields={paddr,pwdata,pstrb};
            if (psel && penable && pready) commits++;
            if (av_readdatavalid || av_writeresponsevalid) begin
                check(responses < accepted && responses < commits,"exactly one response after APB commit");
                check(av_writeresponsevalid===exp_write[responses] && av_readdatavalid===!exp_write[responses],"response direction");
                check(av_response===(exp_addr[responses][8] ? 2'b10 : 2'b00),"APB error propagation");
                if(av_readdatavalid) check(av_readdata===(exp_addr[responses][8] ? 32'd0 : (32'ha5a50000 | exp_addr[responses])),"read response data");
                responses++;
            end
        end
    end
    task issue(input bit wr, input [11:0] addr, input [31:0] data, input [3:0] strb);
        begin
            @(negedge clk); av_address=addr; av_writedata=data;
            av_byteenable=strb; av_write=wr; av_read=!wr;
            @(posedge clk); while(av_waitrequest) @(posedge clk);
            @(negedge clk); av_write=0; av_read=0;
            // Deliberately change inputs before APB completes.
            av_address=12'hbad; av_writedata=32'hdeadbeef; av_byteenable=0;
        end
    endtask
    task reset;
        begin
            @(negedge clk); reset_n=0; av_read=0; av_write=0;
            #1; check(!psel && !penable && !av_readdatavalid && !av_writeresponsevalid,"reset suppresses bus effects");
            repeat(3) @(negedge clk);
            reset_n=1;
        end
    endtask
    initial begin
        reset();
        for(i=0;i<500;i++) issue(i%2, $random(seed), $random(seed), i%16);
        wait(responses==500); @(negedge clk);
        check(commits==500 && accepted==500,"no lost or duplicated transactions");
        // Reset aborts a captured SETUP and an ACCESS waiting at the slave.
        issue(0,0,0,0); reset();
        issue(1,0,32'h55,15); wait(penable && !pready); reset();
        issue(0,12'h24,0,0); wait(responses==1); @(negedge clk);
        check(commits==1,"first transfer after reset succeeds");
        $display("PASS tb_avalon_apb_bridge checks=%0d randomized_commands=500 reset_abort=2",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"bridge watchdog"); end
endmodule
