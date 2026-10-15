package require -exact qsys 16.1
set_module_property NAME uart_avalon
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME {DTI UART with Avalon to APB4 bridge}
set_module_property DESCRIPTION {Single outstanding Avalon-MM command with read and write responses, byte addressing and APB4 error propagation.}
set_module_property AUTHOR {UART Project}
set_module_property GROUP {UART Project}
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
add_parameter CLK_FREQ INTEGER 50000000
set_parameter_property CLK_FREQ HDL_PARAMETER true
add_parameter BAUDRATE INTEGER 115200
set_parameter_property BAUDRATE HDL_PARAMETER true

foreach fs {synthesis simulation} {
    if {$fs eq "synthesis"} {set kind QUARTUS_SYNTH} else {set kind SIM_VERILOG}
    add_fileset $fs $kind {} {}
    set_fileset_property $fs TOP_LEVEL uart_avalon
    foreach name {uart_avalon.v avalon_apb_bridge.v dti_uart.v apb_slave.v register_file.v uart_fifo.v baud_rate_gen.v uart_Tx/tx_topmodule.v uart_Tx/tx_controller.v uart_Tx/tx_datapath.v uart_rx/rx_topmodule.v uart_rx/rx_controller.v uart_rx/rx_datapath.v} {
        add_fileset_file $name VERILOG PATH ../../rtl/$name
    }
}
add_interface clock clock sink
add_interface_port clock clk clk Input 1
add_interface reset reset sink
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1
add_interface avalon avalon end
foreach {prop val} {
    associatedClock clock associatedReset reset addressUnits SYMBOLS
    bitsPerSymbol 8 burstOnBurstBoundariesOnly false
    maximumPendingReadTransactions 1 maximumPendingWriteTransactions 1
    readLatency 0 readWaitTime 0 writeWaitTime 0
} {set_interface_property avalon $prop $val}
foreach {port role dir width} {
    av_address address Input 12
    av_read read Input 1
    av_write write Input 1
    av_writedata writedata Input 32
    av_byteenable byteenable Input 4
    av_waitrequest waitrequest Output 1
    av_readdata readdata Output 32
    av_readdatavalid readdatavalid Output 1
    av_writeresponsevalid writeresponsevalid Output 1
    av_response response Output 2
} {add_interface_port avalon $port $role $dir $width}
add_interface serial conduit end
set_interface_property serial associatedClock clock
set_interface_property serial associatedReset reset
foreach {port dir} {rx Input tx Output cts_n Input rts_n Output} {
    add_interface_port serial $port $port $dir 1
}
