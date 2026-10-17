#!/usr/bin/env bash
# RTL analysis/synthesis only: no fitter, pin assignments, bitstream or hardware.
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
quartus_bin="${QUARTUS_BIN:-/home/kien/altera_lite/25.1std/quartus/bin}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-synthesis.XXXXXX")"
result_dir="$sim_dir/results/quartus"
mkdir -p "$result_dir"
python3 - "$sim_dir" "$build_dir" <<'PY'
from pathlib import Path
import sys
sim, build = map(Path, sys.argv[1:])
lines = ['set_global_assignment -name FAMILY "Cyclone IV E"',
         'set_global_assignment -name DEVICE EP4CE115F29C7',
         'set_global_assignment -name TOP_LEVEL_ENTITY apb_uart',
         'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2']
for name in (sim/'rtl.f').read_text().splitlines():
    if name.strip():
        lines.append('set_global_assignment -name VERILOG_FILE "'+str((sim/name).resolve())+'"')
(build/'uart_check.qsf').write_text('\n'.join(lines)+'\n')
(build/'uart_check.qpf').write_text('PROJECT_REVISION = "uart_check"\n')
PY
cd "$build_dir"
"$quartus_bin/quartus_map" uart_check --read_settings_files=on --write_settings_files=off \
    > "$result_dir/console.log" 2>&1 || { cat "$result_dir/console.log"; exit 1; }
cp uart_check.map.rpt uart_check.map.summary "$result_dir/"
cat "$result_dir/uart_check.map.summary"
