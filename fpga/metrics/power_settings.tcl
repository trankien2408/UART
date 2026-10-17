# The normalized VCD has only the UART top, with testbench/dut scopes removed.
project_open uart_metrics
set_global_assignment -name POWER_USE_INPUT_FILES ON
set_global_assignment -name POWER_INPUT_FILE_NAME activity_mapped.vcd -section_id activity
set_global_assignment -name POWER_INPUT_FILE_TYPE VCD -section_id activity
set_instance_assignment -name POWER_READ_INPUT_FILE activity -to uart_avalon -entity uart_avalon
set_global_assignment -name POWER_AUTO_COMPUTE_TJ OFF
set_global_assignment -name POWER_TJ_VALUE 25
export_assignments
project_close
