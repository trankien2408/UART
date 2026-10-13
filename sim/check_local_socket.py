#!/usr/bin/env python3
"""Check local TCP permission before starting Questa's simulation processes."""
import socket
import sys

stage = "socket()"
try:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        stage = "bind(127.0.0.1)"
        server.bind(("127.0.0.1", 0))
        stage = "listen()"
        server.listen(1)
except OSError as error:
    print(f"BLOCKED: local TCP {stage}: {error}", file=sys.stderr)
    print("Questa needs local sockets to start simulation. No FPGA board is needed.", file=sys.stderr)
    print("Run this script from your normal VS Code/Linux terminal, outside the restricted execution environment:", file=sys.stderr)
    print("  cd /home/kien/Documents/uart", file=sys.stderr)
    print("  bash UART/sim/run_niosv_firmware.sh", file=sys.stderr)
    sys.exit(1)
print("PASS: local TCP socket, bind and listen permitted (Questa/license not checked)")
