#!/usr/bin/env bash
set -euo pipefail
fpga_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$fpga_dir/scripts/env.sh"
cd "$fpga_dir"
mkdir -p build/logs
rm -f build/HARDWARE_BUILD_READY.txt build/ready_manifest.sha256
phase="${1:-all}"
case "$phase" in generate|compile|all) ;; *) echo 'Usage: build.sh [generate|compile|all]' >&2; exit 2;; esac
run_logged() {
    local log="$1"; shift
    "$@" > "$log" 2>&1 || { tail -50 "$log"; return 1; }
    if grep -Eq '(^| )Error[:(]|Error \([0-9]+\)' "$log"; then tail -50 "$log"; return 1; fi
}
if [[ "$phase" != compile ]]; then
    run_logged build/logs/create_system.log qsys-script --script=scripts/create_system.tcl \
        "--search-path=$fpga_dir/ip/**/*,\$"
    run_logged build/logs/generate.log qsys-generate uart_soc.qsys --synthesis=VERILOG \
        --simulation=VERILOG --output-directory=build/uart_soc "--search-path=$fpga_dir/ip/**/*,\$"
    test -s uart_soc.sopcinfo
    test -s build/uart_soc/synthesis/uart_soc.qip
    echo 'PASS Platform Designer generation'
fi
if [[ "$phase" != generate ]]; then
    run_logged build/logs/compile.log quartus_sh --flow compile de2_115_uart
    test -s build/output_files/de2_115_uart.sof
    python3 scripts/check_build.py
fi
