#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo 'Usage: bash UART/firmware/terminal_uart.sh /dev/ttyUSB0' >&2
    echo 'List ports: python3 -m serial.tools.list_ports' >&2
    exit 2
fi
if ! command -v picocom >/dev/null 2>&1; then
    echo 'Missing picocom. Install on Ubuntu: sudo apt install picocom' >&2
    exit 127
fi
# Local echo OFF: ky tu hien ve phai do FPGA tra lai, khong phai PC tu in.
# Enter gui CR+LF; firmware echo nguyen hai byte de xuong dong tren terminal.
# Picocom mac dinh tat local echo; khong them --echo.
echo 'UART: 115200 8N1, no flow control, local echo OFF. Exit: Ctrl+A then Ctrl+X.'
exec picocom --baud 115200 --databits 8 --parity n --stopbits 1 \
    --flow n --omap crcrlf --lower-dtr --lower-rts "$1"
