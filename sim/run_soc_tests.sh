#!/usr/bin/env bash
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$sim_dir"
mkdir -p results/soc
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-soc-tests.XXXXXX")"
finish() {
    local rc=$?
    rm -rf -- "$build_dir"
    if ((rc)); then echo FAILED > results/soc/status.txt; fi
}
trap finish EXIT
echo RUNNING > results/soc/status.txt
for top in tb_avalon_apb_bridge tb_uart_avalon; do
    iverilog -g2012 -Wall -s "$top" -o "$build_dir/$top.vvp" -f rtl.f \
        ../rtl/avalon_apb_bridge.v ../rtl/uart_avalon.v "../tb/$top.v" \
        > "results/soc/$top.compile.log" 2>&1
    timeout 120 vvp "$build_dir/$top.vvp" > "results/soc/$top.log" 2>&1
    grep "PASS $top" "results/soc/$top.log"
done
echo 'ALL SOC RTL TESTS PASSED' | tee results/soc/status.txt
