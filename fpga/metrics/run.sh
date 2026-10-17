#!/usr/bin/env bash
# Isolated fitted characterization: uart_avalon = bridge + complete UART core.
set -euo pipefail
fpga_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$fpga_dir/scripts/env.sh"
metrics_dir="$fpga_dir/build/metrics"
mkdir -p "$metrics_dir/logs"
python3 - "$fpga_dir" "$metrics_dir" <<'PY'
from pathlib import Path
import sys
fpga, build = map(Path, sys.argv[1:])
qsf = ['set_global_assignment -name FAMILY "Cyclone IV E"',
       'set_global_assignment -name DEVICE EP4CE115F29C7',
       'set_global_assignment -name TOP_LEVEL_ENTITY uart_avalon',
       'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
       'set_global_assignment -name NUM_PARALLEL_PROCESSORS 4',
       'set_global_assignment -name SEED 1',
       'set_global_assignment -name SDC_FILE metrics.sdc',
       'set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"',
       'set_location_assignment PIN_Y2 -to clk',
       'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk']
for src in sorted((fpga.parent/'rtl').rglob('*.v')):
    qsf.append(f'set_global_assignment -name VERILOG_FILE "{src}"')
for port in ['reset_n','av_address[*]','av_read','av_write','av_writedata[*]',
             'av_byteenable[*]','av_waitrequest','av_readdata[*]',
             'av_readdatavalid','av_writeresponsevalid','av_response[*]',
             'rx','cts_n','tx','rts_n','irq']:
    qsf.append(f'set_instance_assignment -name VIRTUAL_PIN ON -to "{port}"')
(build/'uart_metrics.qsf').write_text('\n'.join(qsf)+'\n')
(build/'uart_metrics.qpf').write_text('PROJECT_REVISION = "uart_metrics"\n')
(build/'metrics.sdc').write_text('''create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty
# Avalon boundary synchronous to clk; zero external delay for isolated IP characterization.
set_input_delay -clock clk -max 0.0 [get_ports {av_address[*] av_read av_write av_writedata[*] av_byteenable[*]}]
set_input_delay -clock clk -min 0.0 [get_ports {av_address[*] av_read av_write av_writedata[*] av_byteenable[*]}]
set_output_delay -clock clk -max 0.0 [get_ports {av_waitrequest av_readdata[*] av_readdatavalid av_writeresponsevalid av_response[*] irq}]
set_output_delay -clock clk -min 0.0 [get_ports {av_waitrequest av_readdata[*] av_readdatavalid av_writeresponsevalid av_response[*] irq}]
# Reset / serial / CTS asynchronous; serial outputs have no external synchronous clock.
set_false_path -from [get_ports {reset_n rx cts_n}]
set_false_path -to [get_ports {tx rts_n}]
''')
PY
cd "$metrics_dir"
for stage in map fit sta asm; do
    echo "Running quartus_$stage: uart_avalon standalone"
    "quartus_$stage" uart_metrics > "logs/$stage.log" 2>&1 || { tail -60 "logs/$stage.log"; exit 1; }
done
quartus_sta -t "$fpga_dir/metrics/timing_detail.tcl" > logs/timing_detail.log 2>&1
bash "$fpga_dir/metrics/activity.sh"
python3 "$fpga_dir/metrics/prepare_vcd.py" "$metrics_dir/activity.vcd"
quartus_sh -t "$fpga_dir/metrics/power_settings.tcl" > logs/power_settings.log 2>&1
quartus_pow uart_metrics > logs/power.log 2>&1
python3 "$fpga_dir/metrics/summarize.py"
python3 "$fpga_dir/metrics/make_pdf.py"
printf 'PASS fitted resource/timing and VCD-based power analysis: %s\n' "$metrics_dir/output_files"
