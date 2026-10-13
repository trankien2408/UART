#!/usr/bin/env python3
"""Hardware acceptance test; stop-and-wait because the RTL RX buffer is 1 byte."""
import argparse
import random
import serial

parser = argparse.ArgumentParser()
parser.add_argument('port', help='USB-UART serial device, e.g. /dev/ttyUSB0')
parser.add_argument('--count', type=int, default=1024)
args = parser.parse_args()
if args.count <= 0:
    parser.error('--count must be positive')
rng = random.Random(20261011)
patterns = [0, 255, 85, 170, 1, 128, 13, 10]
# Opening some ESP32 boards can pulse EN through the auto-program circuit.
# Hold ESP32 EN low physically while using its USB-UART bridge.
with serial.Serial(args.port, 115200, timeout=1, write_timeout=1,
                   bytesize=8, parity='N', stopbits=1, rtscts=False,
                   xonxoff=False, dsrdtr=False) as port:
    port.reset_input_buffer()
    for i in range(args.count):
        value = patterns[i] if i < len(patterns) else rng.randrange(256)
        expected = bytes([value])
        port.write(expected)
        actual = port.read(1)
        if actual != expected:
            raise SystemExit(f'FAIL byte {i}: sent {expected.hex()}, received {actual.hex() or "TIMEOUT"}')
    if port.read(1):
        raise SystemExit('FAIL: unexpected extra/duplicated echo')
print(f'PASS external UART echo: {args.count} bytes at 115200 8N1')
