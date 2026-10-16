# Chat uses UART IRQ; scope/selftest use polling. Timeouts read mtime; JTAG uses raw MMIO.
set_setting hal.enable_reduced_device_drivers true
set_setting hal.sys_clk_timer none
set_setting hal.timestamp_timer none
set_setting hal.STDIN none
set_setting hal.STDOUT none
set_setting hal.STDERR none
