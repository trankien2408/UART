#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo 'Usage: bash UART/firmware/terminal_uart.sh /dev/ttyUSB0 [baud=115200]' >&2
    echo 'List ports: python3 -m serial.tools.list_ports' >&2
    exit 2
fi
baud="${2:-115200}"
if [[ ! "$baud" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Baud must be a positive integer.' >&2; exit 2
fi
if ! command -v picocom >/dev/null 2>&1; then
    echo 'Missing picocom. Install on Ubuntu: sudo apt install picocom' >&2
    exit 127
fi
firmware_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Retain picocom's UI; expose real driver error flags / invisible received bytes.
# Set UART_TERMINAL_PLAIN=1 for the original unfiltered binary view.
if [[ "${UART_TERMINAL_PLAIN:-0}" != 1 ]]; then
    exec python3 "$firmware_dir/serial_diagnostics.py" "$1" "$baud"
fi
# Local echo OFF: ky tu hien ve phai do FPGA tra lai, khong phai PC tu in.
# Enter gui CR+LF; firmware echo nguyen hai byte de xuong dong tren terminal.
# Picocom mac dinh tat local echo; khong them --echo.
echo "UART: $baud 8N1, no flow control, local echo OFF. Exit: Ctrl+A then Ctrl+X."
exec picocom --baud "$baud" --databits 8 --parity n --stopbits 1 \
    --flow n --omap crcrlf --lower-dtr --lower-rts "$1"
