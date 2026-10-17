#!/usr/bin/env bash
set -euo pipefail
fpga_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
metrics_dir="$fpga_dir/build/metrics"
mkdir -p "$metrics_dir/logs"
mapfile -t rtl_files < <(rg --files "$fpga_dir/../rtl" -g '*.v' | sort)
iverilog -g2012 -s tb_uart_power -o "$metrics_dir/activity.vvp" "${rtl_files[@]}" "$fpga_dir/metrics/tb_uart_power.v"
cd "$metrics_dir"
vvp activity.vvp > logs/activity.log
cat logs/activity.log
