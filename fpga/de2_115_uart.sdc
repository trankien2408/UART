create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty
# External KEY and UART inputs are asynchronous. Internal synchronizer stages
# and the internal loopback path retain normal CLOCK_50 timing constraints.
set_false_path -from [get_ports {KEY0 UART_RX UART_CTS_N}]
# UART and LED outputs have no synchronous receiving clock on the board.
set_false_path -to [get_ports {UART_TX UART_RTS_N LEDG[*]}]
