#!/usr/bin/env bash
set -euo pipefail
fpga_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$fpga_dir/scripts/env.sh"
cd "$fpga_dir"
# Public arguments follow quartus_pgm: cable and device positions start at 1.
cable="${1:-1}"; device="${2:-1}"
target="${3:-echo}"
if [[ $# -gt 3 || ! "$cable" =~ ^[1-9][0-9]*$ || ! "$device" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: bash UART/fpga/program.sh [cable>=1] [Quartus device position>=1] [echo|scope]' >&2
    exit 2
fi
case "$target" in
    echo) elf="$fpga_dir/../firmware/build/app/build/uart_firmware.elf"
          firmware_manifest=../firmware/build/ready_manifest.sha256 ;;
    scope) elf="$fpga_dir/../firmware/build/scope/build/uart_scope.elf"
           firmware_manifest=../firmware/build/scope_manifest.sha256 ;;
    *) echo 'Firmware target must be echo or scope.' >&2; exit 2 ;;
esac
# Nios V/OpenOCD and juart-terminal number devices from 0; cable stays 1-based.
nios_device=$((10#$device - 1))
test -s build/HARDWARE_BUILD_READY.txt || {
    echo 'No validated hardware build marker. Run build.sh compile and resolve license/timing errors.' >&2; exit 1;
}
sha256sum --check --quiet build/ready_manifest.sha256
test -s "$elf" || { echo 'Build firmware ELF first.' >&2; exit 1; }
sha256sum --check --quiet "$firmware_manifest"
mkdir -p build/logs
program_log_dir="$(mktemp -d "$fpga_dir/build/logs/program.XXXXXX")"
printf '%s\n' "$program_log_dir" > build/logs/latest_program_directory.txt
echo "Programming logs: $program_log_dir"
run_logged() {
    local log_name="$1"; shift
    "$@" 2>&1 | tee "$program_log_dir/$log_name"
}
run_logged jtag_before.log timeout 30 jtagconfig --debug
echo "Programming Quartus device $device; Nios V device index $nios_device (cable $cable)."
run_logged quartus_pgm.log quartus_pgm -m jtag -c "$cable" -o "p;build/output_files/de2_115_uart.sof@$device"
# Observe the configured fabric, not just the physical FPGA IDCODE.
echo 'Expected nodes in this build: Nios V 08986E00; JTAG UART 0C006E00.'
run_logged jtag_after.log timeout 30 jtagconfig --debug
if ! run_logged niosv_download.log niosv-download -c "$cable" -d "$nios_device" -r -g "$elf"; then
    echo 'CPU download failed; collecting the debugger view of the JTAG chain.' >&2
    run_logged openocd_scan.log timeout 30 openocd-cfg-gen --print --cable="$cable" || true
    echo "Download is NOT complete. Inspect logs in $program_log_dir" >&2
    exit 1
fi
echo "Downloaded $target firmware successfully."
if [[ "$target" == scope ]]; then
    echo 'Scope: UART TX sends hello, then waits 100 ms; no JTAG text is printed.'
else
    echo 'Open juart-terminal for logs and a 115200 8N1 serial terminal for UART echo.'
fi
echo "JTAG terminal: bash UART/firmware/terminal_jtag.sh -c $cable -d $nios_device"
