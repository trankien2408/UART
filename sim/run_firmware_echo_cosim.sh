#!/usr/bin/env bash
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-echo-cosim.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
result_dir="$sim_dir/results/firmware_echo_cosim"
mkdir -p "$result_dir"
cd "$build_dir"
iverilog-vpi --name=firmware_cosim -DUART_HOST_TEST -DUART_DEMO_TEST -DUART_ECHO_COSIM \
    -I"$sim_dir/../firmware" -I"$sim_dir/../firmware/tests" -I"$sim_dir/../firmware/build/bsp" \
    "$sim_dir/../tb/firmware_cosim.c" "$sim_dir/../firmware/main.c" \
    "$sim_dir/../firmware/uart_irq.c" "$sim_dir/../firmware/console.c" "$sim_dir/../firmware/dti_uart.c" -lpthread \
    > "$result_dir/compile_c.log" 2>&1
cd "$sim_dir"
iverilog -g2012 -Wall -s tb_firmware_echo_cosim -o "$build_dir/test.vvp" -f rtl.f \
    ../rtl/avalon_apb_bridge.v ../rtl/uart_avalon.v ../tb/tb_firmware_echo_cosim.v \
    > "$result_dir/compile_rtl.log" 2>&1
timeout 180 vvp -M "$build_dir" -m firmware_cosim "$build_dir/test.vvp" \
    > "$result_dir/run.log" 2>&1
grep '^PASS firmware_echo_cosim:' "$result_dir/run.log"
