#!/usr/bin/env bash
# Run from anywhere. This script never uses or deletes the user's work library.
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$sim_dir"
engine="${UART_SIMULATOR:-auto}"
compile_only=0
while (($#)); do
    case "$1" in
        --compile-only) compile_only=1; shift ;;
        --simulator) engine="$2"; shift 2 ;;
        *) echo "Usage: $0 [--compile-only] [--simulator auto|iverilog|questa]" >&2; exit 2 ;;
    esac
done
questa_bin="${QUESTA_BIN:-/home/kien/altera_lite/25.1std/questa_fse/bin}"
if [[ "$engine" == auto ]]; then
    if command -v iverilog >/dev/null && command -v vvp >/dev/null; then
        engine=iverilog
    else
        engine=questa
    fi
fi
if [[ "$engine" != iverilog && "$engine" != questa ]]; then
    echo "Unknown simulator: $engine" >&2; exit 2
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-regression.XXXXXX")"
result_dir="$sim_dir/results/$engine"
mkdir -p "$result_dir"
echo 'RUNNING' > "$result_dir/status.txt"
finish() {
    local rc=$?
    if ((rc)); then printf 'FAILED (exit %s); see logs.\n' "$rc" > "$result_dir/status.txt"; fi
}
trap finish EXIT
# Keep the temporary build location in the log for reproducibility/debugging.
printf 'Simulator: %s\nBuild: %s\n' "$engine" "$build_dir" | tee "$result_dir/run_info.txt"
test_sources=(../tb/tb_uart_fifo.sv ../tb/tb_dti_uart.sv ../tb/tb_register_file.sv ../tb/tb_baud_rate_check.sv)
{ date -Iseconds; while IFS= read -r source; do sha256sum "$source"; done < rtl.f;
  sha256sum "${test_sources[@]}" run_tests.sh; } > "$result_dir/source_manifest.txt"
if [[ "$engine" == questa ]]; then
    "$questa_bin/vlib" "$build_dir/work"
    "$questa_bin/vlog" -lint -sv -work "$build_dir/work" -f rtl.f "${test_sources[@]}" \
        2>&1 | tee "$result_dir/compile.log"
else
    for top in tb_uart_fifo tb_dti_uart tb_register_file tb_baud_rate_check; do
        iverilog -g2012 -Wall -s "$top" -o "$build_dir/$top.vvp" -f rtl.f "${test_sources[@]}"
    done 2>&1 | tee "$result_dir/compile.log"
fi
if ((compile_only)); then
    echo 'COMPILE ONLY complete; simulation has not run.' | tee "$result_dir/status.txt"
    exit 0
fi
run_test() {
    local name="$1" top="$2" baud="${3:-115200}" smoke="${4:-0}" seed="${5:-12345}"
    local log="$result_dir/$name.log"
    echo "Running $name"
    if [[ "$engine" == questa ]]; then
        local params=()
        if [[ "$top" == tb_dti_uart ]]; then params=(-gBAUDRATE="$baud" -gSMOKE="$smoke"); fi
        timeout 180 "$questa_bin/vsim" -batch -onfinish exit -lib "$build_dir/work" "$top" \
            "${params[@]}" +SEED="$seed" \
            -do 'onerror {quit -code 1 -f}; run -all; quit -code 0 -f' -l "$log" \
            > "$result_dir/$name.console.log" 2>&1 || {
                cat "$result_dir/$name.console.log"; return 1;
            }
    else
        local executable="$build_dir/$top.vvp"
        if [[ "$top" == tb_dti_uart ]]; then
            executable="$build_dir/$name.vvp"
            iverilog -g2012 -Wall -s "$top" -P "tb_dti_uart.BAUDRATE=$baud" \
                -P "tb_dti_uart.SMOKE=$smoke" -o "$executable" -f rtl.f "${test_sources[@]}"
        fi
        timeout 180 vvp "$executable" +SEED="$seed" > "$log" 2>&1 || { cat "$log"; return 1; }
    fi
    # Some simulator startup failures return 0; require the testbench PASS marker.
    if ! grep -q "PASS $top" "$log"; then cat "$log"; echo "Missing PASS: $name" >&2; return 1; fi
    grep "PASS $top" "$log"
}
run_test uart_fifo tb_uart_fifo
run_test register_file tb_register_file
run_test baud_rate tb_baud_rate_check
run_test integration_115200_seed12345 tb_dti_uart 115200 0 12345
run_test integration_115200_seed20261011 tb_dti_uart 115200 0 20261011
for baud in 2400 4800 9600 19200 38400 57600 76800 230400; do
    run_test "smoke_$baud" tb_dti_uart "$baud" 1
done
echo 'ALL TESTS PASSED' | tee "$result_dir/status.txt"
