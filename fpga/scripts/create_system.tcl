package require -exact qsys 25.1
create_system uart_soc
set_project_property DEVICE_FAMILY {Cyclone IV E}
set_project_property DEVICE EP4CE115F29C7
set_project_property HIDE_FROM_IP_CATALOG false

add_instance clk clock_source
set_instance_parameter_value clk clockFrequency 50000000
set_instance_parameter_value clk clockFrequencyKnown true
set_instance_parameter_value clk resetSynchronousEdges DEASSERT
add_instance cpu intel_niosv_m
set_instance_parameter_value cpu enableAvalonInterface true
set_instance_parameter_value cpu enableDebug true
set_instance_parameter_value cpu enableDebugReset true
set_instance_parameter_value cpu resetSlave ram.s1
set_instance_parameter_value cpu resetOffset 0
add_instance ram altera_avalon_onchip_memory2
set_instance_parameter_value ram memorySize 131072
set_instance_parameter_value ram dataWidth 32
set_instance_parameter_value ram initMemContent true
set_instance_parameter_value ram dualPort false
add_instance jtag_uart altera_avalon_jtag_uart
add_instance sysid altera_avalon_sysid_qsys
set_instance_parameter_value sysid id 1430344276
add_instance control altera_avalon_pio
set_instance_parameter_value control width 4
set_instance_parameter_value control direction Output
set_instance_parameter_value control resetValue 0
add_instance uart uart_avalon 1.0

foreach target {cpu.clk ram.clk1 jtag_uart.clk sysid.clk control.clk uart.clock} {
    add_connection clk.clk $target
}
foreach target {cpu.reset ram.reset1 jtag_uart.reset sysid.reset control.reset uart.reset} {
    add_connection clk.clk_reset $target
}
foreach target {cpu.ndm_reset_in ram.reset1 jtag_uart.reset sysid.reset control.reset uart.reset} {
    add_connection cpu.dbg_reset_out $target
}
foreach manager {cpu.instruction_manager cpu.data_manager} {
    foreach {agent base} {ram.s1 0x00000000 cpu.dm_agent 0x00100000} {
        add_connection $manager $agent
        set_connection_parameter_value $manager/$agent baseAddress $base
    }
}
foreach {agent base} {
    jtag_uart.avalon_jtag_slave 0x00020000
    sysid.control_slave 0x00020008
    control.s1 0x00020010
    uart.avalon 0x00021000
    cpu.timer_sw_agent 0x00030000
} {
    add_connection cpu.data_manager $agent
    set_connection_parameter_value cpu.data_manager/$agent baseAddress $base
}
add_connection cpu.platform_irq_rx jtag_uart.irq
set_connection_parameter_value cpu.platform_irq_rx/jtag_uart.irq irqNumber 0
foreach {name type direction internal} {
    clk clock sink clk.clk_in
    reset reset sink clk.clk_in_reset
    control conduit end control.external_connection
    uart conduit end uart.serial
} {
    add_interface $name $type $direction
    set_interface_property $name EXPORT_OF $internal
}
save_system uart_soc.qsys
