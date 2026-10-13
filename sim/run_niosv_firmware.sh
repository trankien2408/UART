#!/usr/bin/env bash
set -euo pipefail
sim_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export UART_PROJECT_ROOT="$(cd "$sim_dir/.." && pwd)"
source "$UART_PROJECT_ROOT/fpga/scripts/env.sh"
export UART_SOC_COMPILE_ONLY=0
if [[ "${1:-}" == --compile-only ]]; then export UART_SOC_COMPILE_ONLY=1; fi
if [[ "$UART_SOC_COMPILE_ONLY" != 1 ]]; then
test -s "$UART_PROJECT_ROOT/firmware/build/app/build/ram.hex" || {
    echo 'Missing compiled firmware ram.hex; run firmware/build.sh first.' >&2; exit 1;
}
fi
questa_bin="${QUESTA_BIN:-$UART_QUARTUS_ROOT/questa_fse/bin}"
result_dir="$sim_dir/results/niosv_firmware"
if [[ "$UART_SOC_COMPILE_ONLY" == 1 ]]; then result_dir="${result_dir}_compile"; fi
mkdir -p "$result_dir"
# Hold the lock before touching status/logs. A second run must not truncate
# files still being written by the first Questa process.
exec 9> "$result_dir/.run.lock"
if ! flock -n 9; then
    echo 'UART_SIM: another simulation is running; wait for it or stop it with Ctrl+C.' >&2
    exit 1
fi
archive_dir="$(mktemp -d "$result_dir/run.XXXXXX")"
for log_name in console.log transcript.log status.txt work_directory.txt socket_check.log; do
    if [[ -f "$result_dir/$log_name" && ! -L "$result_dir/$log_name" ]]; then
        mv "$result_dir/$log_name" "$archive_dir/previous_$log_name"
    fi
    ln -sfn "$(basename "$archive_dir")/$log_name" "$result_dir/$log_name"
done
# Use unique paths so even a process started with the old script cannot mix
# its output with this run. The stable names above link to this latest run.
result_dir="$archive_dir"
echo "UART_SIM: logs: $result_dir"
if [[ "$UART_SOC_COMPILE_ONLY" != 1 ]]; then
    if ! python3 "$sim_dir/check_local_socket.py" > "$result_dir/socket_check.log" 2>&1; then
        cat "$result_dir/socket_check.log"
        echo 'BLOCKED: local TCP socket permission' > "$result_dir/status.txt"
        exit 1
    fi
fi
echo RUNNING > "$result_dir/status.txt"
trap 'rc=$?; if ((rc)); then echo FAILED > "$result_dir/status.txt"; fi' EXIT
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/uart-niosv-sim.XXXXXX")"
printf '%s\n' "$build_dir" > "$result_dir/work_directory.txt"
cd "$build_dir"
echo "UART_SIM: starting Questa; wall-clock limit 600 seconds"
if timeout 600 "$questa_bin/vsim" -c -do "$sim_dir/niosv_firmware.do" \
    -l "$result_dir/transcript.log" 2>&1 | tee "$result_dir/console.log" | \
    awk '/UART_SIM:|PASS |Nios V firmware|firmware echo:|watchdog|couldn.t open socket|Trouble making server|\*\* (Error|Fatal)/ { print; fflush(); }'; then
    :
else
    rc=$?
    if [[ "$rc" == 124 ]]; then echo 'UART_SIM: wall-clock timeout (600 seconds), simulation did not finish.'; fi
    tail -40 "$result_dir/console.log"
    exit "$rc"
fi
if [[ "$UART_SOC_COMPILE_ONLY" == 1 ]]; then
    grep 'PASS Nios V simulation compile only' "$result_dir/console.log"
    echo 'COMPILE ONLY (no CPU execution)' > "$result_dir/status.txt"
else
    grep 'PASS tb_niosv_firmware:' "$result_dir/console.log" || {
        tail -30 "$result_dir/console.log"; exit 1;
    }
    echo 'PASS full Nios V firmware simulation' > "$result_dir/status.txt"
fi
