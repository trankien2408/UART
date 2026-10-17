project_open uart_metrics
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths 10 -detail full_path -file output_files/critical_setup.rpt
report_timing -hold -npaths 5 -detail full_path -file output_files/critical_hold.rpt
report_clock_fmax_summary -file output_files/fmax_detail.rpt
report_ucp -file output_files/unconstrained_detail.rpt
delete_timing_netlist
project_close
