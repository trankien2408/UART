#!/usr/bin/env bash
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-firmware-cosim.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
mkdir -p "$sim_dir/results/firmware_cosim"
cd "$build_dir"
iverilog-vpi --name=firmware_cosim -DUART_HOST_TEST -I"$sim_dir/../firmware" -I"$sim_dir/../firmware/tests" \
    "$sim_dir/../tb/firmware_cosim.c" "$sim_dir/../firmware/dti_uart.c" \
    "$sim_dir/../firmware/tests/uart_selftest.c" -lpthread \
    > "$sim_dir/results/firmware_cosim/compile_c.log" 2>&1
cd "$sim_dir"
iverilog -g2012 -Wall -s tb_firmware_cosim -o "$build_dir/test.vvp" -f rtl.f \
    ../rtl/avalon_apb_bridge.v ../rtl/uart_avalon.v ../tb/tb_firmware_cosim.v \
    > results/firmware_cosim/compile_rtl.log 2>&1
timeout 300 vvp -M "$build_dir" -m firmware_cosim "$build_dir/test.vvp" \
    > results/firmware_cosim/run.log 2>&1
grep '^PASS firmware_cosim:' results/firmware_cosim/run.log
