#!/usr/bin/env python3
"""Hardware chat acceptance: burst ASCII lines, check local echo and CRLF.
Close picocom first. This checks the physical UART path, not JTAG delivery.
"""
import argparse
import random
import serial

parser = argparse.ArgumentParser()
parser.add_argument('port', help='USB-UART serial device, e.g. /dev/ttyUSB0')
parser.add_argument('--count', type=int, default=1024, help='number of printable payload bytes')
args = parser.parse_args()
if args.count <= 0:
    parser.error('--count must be positive')
rng = random.Random(20261011)
# Hold ESP32 EN low physically while using its USB-UART bridge.
with serial.Serial(args.port, 115200, timeout=2, write_timeout=2,
                   bytesize=8, parity='N', stopbits=1, rtscts=False,
                   xonxoff=False, dsrdtr=False) as port:
    port.reset_input_buffer()
    remaining = args.count
    lines = 0
    while remaining:
        length = min(remaining, 120 if lines == 0 else rng.randint(1, 120))
        payload = bytes(rng.randrange(32, 127) for _ in range(length))
        ending = (b'\r', b'\n', b'\r\n')[lines % 3]
        expected = payload + b'\r\n'
        port.write(payload + ending)
        actual = port.read(len(expected))
        if actual != expected:
            raise SystemExit(f'FAIL line {lines}: expected {expected!r}, received {actual!r}')
        remaining -= length
        lines += 1
    if port.read(1):
        raise SystemExit('FAIL: unexpected extra/duplicated echo')
print(f'PASS external UART chat echo: {args.count} payload bytes, {lines} burst lines, CR/LF/CRLF, 115200 8N1')
