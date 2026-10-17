#!/usr/bin/env python3
"""Parser tests plus real picocom/PTY relay and baud-change integration."""
import importlib.util
import fcntl
import os
from pathlib import Path
import select
import subprocess
import struct
import sys
import termios
import time
import tty
import unittest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('serial_diagnostics', HERE/'serial_diagnostics.py')
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)


class DisplayTests(unittest.TestCase):
    def test_ascii_unchanged_and_nontext_visible(self):
        d = diag.RxDisplay()
        self.assertEqual(d.feed(b'hello\r\n\b\t'), b'hello\r\n\b\t')
        self.assertEqual(d.feed(b'\x00\x1b\x80\xff\xff'), b'[0x00][0x1B][0x80][0xFF]')
        self.assertEqual(d.errors, 0)

    def test_error_markers_every_possible_split(self):
        data = b'A\xff\x00ZB\xff\xffC\xff\x00\x00D'
        expected = (b'A\r\n[UART RX ERROR: FRAME/PARITY; byte=0x5A]\r\n'
                    b'B[0xFF]C\r\n[UART RX ERROR: BREAK/FRAME/PARITY]\r\nD')
        for split in range(len(data)+1):
            d = diag.RxDisplay()
            self.assertEqual(d.feed(data[:split])+d.feed(data[split:]), expected)
            self.assertEqual(d.errors, 2)
        d = diag.RxDisplay()
        self.assertEqual(b''.join(d.feed(bytes((b,))) for b in data), expected)

    def test_literal_ff_is_not_a_hardware_error(self):
        d = diag.RxDisplay()
        self.assertEqual(d.feed(b'\xff'), b'')
        self.assertEqual(d.feed(b'\xff'), b'[0xFF]')
        self.assertEqual(d.errors, 0)

    def test_error_marking_flags(self):
        master, slave = os.openpty()
        try:
            tty.setraw(slave)
            diag.enable_error_marking(slave)
            flags = termios.tcgetattr(slave)[0]
            self.assertTrue(flags & termios.PARMRK)
            self.assertTrue(flags & termios.INPCK)
            self.assertFalse(flags & (termios.IGNPAR | termios.IGNBRK | termios.ISTRIP))
        finally:
            os.close(master);os.close(slave)

    def test_actual_picocom_relay_and_ctrl_b(self):
        # Physical link is a PTY, not an FPGA. No hardware BER claim is made.
        physical_master, physical_slave = os.openpty()
        console_master, console_slave = os.openpty()
        tty.setraw(physical_slave)
        tty.setraw(console_slave)
        fcntl.ioctl(console_slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,120,0,0))
        proc = subprocess.Popen([sys.executable, str(HERE/'serial_diagnostics.py'),
                                 os.ttyname(physical_slave), '115200'],
                                stdin=console_slave, stdout=console_slave, stderr=console_slave,
                                start_new_session=True)
        captured = bytearray()
        def wait_for(fd, expected, seconds=5):
            deadline = time.monotonic()+seconds
            received = bytearray()
            while time.monotonic()<deadline:
                readable, _, _ = select.select([fd], [], [], .05)
                if readable:
                    chunk=os.read(fd, 65536)
                    received.extend(chunk)
                    # picocom asks the terminal emulator for cursor position
                    # before its Ctrl+B prompt. Emulate that standard reply.
                    if fd==console_master and b'\x1b[6n' in chunk:
                        os.write(console_master,b'\x1b[24;1R')
                    if expected in received:
                        if fd==console_master:captured.extend(received)
                        return received
                if proc.poll() is not None:
                    self.fail(f'picocom relay exited {proc.returncode}: {bytes(received)!r}')
            self.fail(f'Timed out waiting for {expected!r}: {bytes(received)!r}; previous={bytes(captured)!r}')
        try:
            wait_for(console_master,b'Terminal ready')
            os.write(console_master,b'abc\r')
            self.assertIn(b'abc\r\n',wait_for(physical_master,b'abc\r\n'))
            os.write(physical_master,b'hello\r\n\x00\x1b\xff')
            wait_for(console_master,b'[0x00][0x1B][0xFF]')
            for rate in (9600,62500,115200):
                os.write(console_master,b'\x01\x02')  # Ctrl+A, Ctrl+B
                wait_for(console_master,b'*** baud: ')
                os.write(console_master,str(rate).encode()+b'\r')
                # Drain the complete confirmation. Its prefix also contains
                # "*** baud: " and must not be mistaken for the next prompt.
                wait_for(console_master,f'*** baud: {rate} ***'.encode())
                deadline=time.monotonic()+5
                while diag.port_settings(physical_slave)[0]!=rate and time.monotonic()<deadline:
                    time.sleep(.02)
                if diag.port_settings(physical_slave)[0]!=rate:
                    readable,_,_=select.select([console_master],[],[],.1)
                    extra=os.read(console_master,65536) if readable else b''
                    self.fail(f'Baud was not propagated; output={bytes(captured)!r}; extra={extra!r}; rc={proc.poll()}')
            os.write(console_master,b'new\r')
            wait_for(physical_master,b'new\r\n')
            os.write(console_master,b'\x01\x18')  # Ctrl+A, Ctrl+X
            self.assertEqual(proc.wait(timeout=5),0)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:proc.wait(timeout=3)
                except subprocess.TimeoutExpired:proc.kill();proc.wait()
            for fd in (physical_master,physical_slave,console_master,console_slave):os.close(fd)


if __name__=='__main__':
    unittest.main(verbosity=2)
