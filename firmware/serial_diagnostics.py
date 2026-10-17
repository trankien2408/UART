#!/usr/bin/env python3
"""Keep picocom's UI, expose real Linux UART error flags and invisible bytes.

The real serial device is owned here; picocom uses a PTY. Its baud/format
changes (including Ctrl+A Ctrl+B) are copied to the real device. No marker
is transmitted to the FPGA. This is an ASCII chat viewer, not a BER meter.
"""
import argparse
import array
import fcntl
import os
import select
import struct
import subprocess
import sys
import termios
import time
import tty

import serial


class RxDisplay:
    """Incremental Linux PARMRK parser; reads can split either marker prefix."""
    def __init__(self):
        self.state = 0
        self.errors = 0

    @staticmethod
    def display_byte(value):
        if 32 <= value <= 126 or value in (8, 9, 10, 13):
            return bytes((value,))
        return f'[0x{value:02X}]'.encode('ascii')

    def feed(self, data):
        output = bytearray()
        for value in data:
            if self.state == 0:
                if value == 255:
                    self.state = 1
                else:
                    output.extend(self.display_byte(value))
            elif self.state == 1:
                if value == 0:
                    self.state = 2
                elif value == 255:
                    output.extend(self.display_byte(255))
                    self.state = 0
                else:
                    # A malformed marker is not a UART bit-error assertion.
                    output.extend(b'[PARMRK INVALID]')
                    output.extend(self.display_byte(value))
                    self.state = 0
            else:
                self.errors += 1
                if value == 0:
                    output.extend(b'\r\n[UART RX ERROR: BREAK/FRAME/PARITY]\r\n')
                else:
                    output.extend(f'\r\n[UART RX ERROR: FRAME/PARITY; byte=0x{value:02X}]\r\n'.encode())
                self.state = 0
        return bytes(output)


def enable_error_marking(fd):
    attrs = termios.tcgetattr(fd)
    attrs[0] &= ~(termios.IGNPAR | termios.IGNBRK | termios.BRKINT |
                  termios.ISTRIP | termios.INLCR | termios.IGNCR | termios.ICRNL)
    attrs[0] |= termios.PARMRK | termios.INPCK
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def port_settings(fd):
    attrs = termios.tcgetattr(fd)
    # Linux termios2 also reports custom rates set by picocom with BOTHER.
    raw = bytearray(44)
    try:
        fcntl.ioctl(fd, 0x802C542A, raw, True)  # TCGETS2, asm-generic ABI
        rate = struct.unpack('=IIIIB19sII', raw)[-1]
    except OSError:
        rates = {getattr(termios, k): int(k[1:]) for k in dir(termios)
                 if k.startswith('B') and k[1:].isdigit()}
        rate = rates.get(attrs[5], 0)
    if not rate:
        raise ValueError('Cannot determine picocom baud rate')
    cflag = attrs[2]
    bits = {termios.CS5: 5, termios.CS6: 6, termios.CS7: 7, termios.CS8: 8}[cflag & termios.CSIZE]
    parity = serial.PARITY_NONE
    if cflag & termios.PARENB:
        parity = serial.PARITY_ODD if cflag & termios.PARODD else serial.PARITY_EVEN
        if cflag & getattr(termios, 'CMSPAR', 0):
            parity = serial.PARITY_MARK if cflag & termios.PARODD else serial.PARITY_SPACE
    return (rate, bits, parity, 2 if cflag & termios.CSTOPB else 1,
            bool(cflag & getattr(termios, 'CRTSCTS', 0)), bool(attrs[0] & termios.IXON))


def synchronize(port, slave_fd, previous):
    settings = port_settings(slave_fd)
    if settings != previous:
        rate, bits, parity, stops, rtscts, xonxoff = settings
        port.apply_settings(dict(baudrate=rate, bytesize=bits, parity=parity,
                                 stopbits=stops, rtscts=rtscts, xonxoff=xonxoff))
        # pyserial resets input flags when reconfiguring, so re-enable PARMRK.
        enable_error_marking(port.fileno())
    return settings


def counters(fd):
    values = array.array('i', [0] * 20)
    try:
        fcntl.ioctl(fd, termios.TIOCGICOUNT, values, True)
    except OSError:
        return None  # Many USB-UART drivers do not expose these counters.
    return {name: values[index] & 0xffffffff for name, index in
            [('FRAME', 6), ('OVERRUN', 7), ('PARITY', 8), ('BREAK', 9), ('BUFFER_OVERRUN', 10)]}


def run(port_name, baud):
    port = serial.Serial(port=None, baudrate=baud, bytesize=8, parity='N',
                         stopbits=1, timeout=0, write_timeout=0, exclusive=True)
    port.dtr = False
    port.rts = False
    port.port = port_name
    master = slave = None
    child = None
    try:
        port.open()
        enable_error_marking(port.fileno())
        master, slave = os.openpty()
        tty.setraw(slave)
        # Set baud before launch so the first synchronization cannot select 38400.
        attrs = termios.tcgetattr(slave)
        rate_constant = getattr(termios, f'B{baud}', None)
        if rate_constant is not None:
            attrs[4] = attrs[5] = rate_constant
            termios.tcsetattr(slave, termios.TCSANOW, attrs)
        else:
            raw = bytearray(44)
            fcntl.ioctl(slave, 0x802C542A, raw, True)
            fields = list(struct.unpack('=IIIIB19sII', raw))
            fields[2] = (fields[2] & ~0x100f) | 0x1000  # CBAUD / BOTHER
            fields[-2:] = [baud, baud]
            fcntl.ioctl(slave, 0x402C542B, struct.pack('=IIIIB19sII', *fields))
        print(f'UART diagnostics: {port_name}, {baud} 8N1; picocom UI.\n'
              'Baud: Ctrl+A then Ctrl+B. Exit: Ctrl+A then Ctrl+X.\n'
              '[0xNN] = non-text byte; [UART RX ERROR] = driver-reported error.\n'
              'No bit-error count is inferred from these markers.', flush=True)
        child = subprocess.Popen(['picocom', '--baud', str(baud), '--databits', '8',
                                  '--parity', 'n', '--stopbits', '1', '--flow', 'n',
                                  '--omap', 'crcrlf', '--noreset', os.ttyname(slave)])
        os.set_blocking(master, False)
        settings = (baud, 8, 'N', 1, False, False)
        decoder = RxDisplay()
        to_serial, to_picocom = bytearray(), bytearray()
        previous_counts = counters(port.fileno())
        previous_errors = 0
        check_at = time.monotonic() + .25
        # Wait until picocom configures the PTY; normal rates already match above.
        while child.poll() is None:
            settings = synchronize(port, slave, settings)
            readable, writable, _ = select.select(
                [master, port.fileno()],
                ([master] if to_picocom else []) + ([port.fileno()] if to_serial else []), [], .02)
            if master in readable:
                to_serial.extend(os.read(master, 4096))
                # A Ctrl+B change may occur while select() sleeps.
                settings = synchronize(port, slave, settings)
            if port.fileno() in readable:
                data = os.read(port.fileno(), 4096)
                if not data:
                    raise OSError('Serial device disconnected')
                to_picocom.extend(decoder.feed(data))
            if port.fileno() in writable and to_serial:
                try:
                    count = os.write(port.fileno(), to_serial[:4096])
                    del to_serial[:count]
                except BlockingIOError:
                    pass
            if master in writable and to_picocom:
                try:
                    count = os.write(master, to_picocom[:4096])
                    del to_picocom[:count]
                except BlockingIOError:
                    pass
            now = time.monotonic()
            if now >= check_at:
                current = counters(port.fileno())
                if current is not None and previous_counts is not None:
                    had_markers = decoder.errors != previous_errors
                    for name, value in current.items():
                        delta = (value - previous_counts[name]) & 0xffffffff
                        if delta and not (had_markers and name in ('FRAME', 'PARITY', 'BREAK')):
                            to_picocom.extend(f'\r\n[UART RX ERROR: {name}; events=+{delta}]\r\n'.encode())
                previous_counts, previous_errors = current, decoder.errors
                check_at = now + .25
            if len(to_serial) > 1048576 or len(to_picocom) > 1048576:
                raise BufferError('Diagnostic relay queue exceeded 1 MiB')
        return child.returncode
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        for fd in (master, slave):
            if fd is not None:
                os.close(fd)
        port.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port')
    parser.add_argument('baud', nargs='?', type=int, default=115200)
    args = parser.parse_args()
    if args.baud <= 0:
        parser.error('baud must be positive')
    try:
        return run(args.port, args.baud)
    except (OSError, ValueError, BufferError, serial.SerialException) as exc:
        print(f'\r\nUART diagnostics stopped: {exc}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
