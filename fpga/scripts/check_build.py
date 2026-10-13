#!/usr/bin/env python3
"""Fail on negative STA slack; report licensing separately from compilation."""
from pathlib import Path
import re
import hashlib
root = Path(__file__).resolve().parents[1]
out = root / 'build/output_files'
timing = (out / 'de2_115_uart.sta.summary').read_text()
slacks = [float(x) for x in re.findall(r'^Slack\s*:\s*([-+\d.]+)', timing, re.M)]
if not slacks or min(slacks) < 0:
    raise SystemExit('FAIL timing: missing results or negative slack')
for phase in ('map', 'fit'):
    if 'Successful' not in (out / f'de2_115_uart.{phase}.summary').read_text():
        raise SystemExit(f'FAIL {phase}')
print(f'PASS Quartus compile and constrained STA paths: worst slack {min(slacks):.3f} ns')
log = (root / 'build/logs/compile.log').read_text()
ready = root / 'build/HARDWARE_BUILD_READY.txt'
if ready.exists():
    ready.unlink()
if re.search(r'Failed to acquire license|Evaluation Mode \(Simulation-Only\)', log):
    for line in log.splitlines():
        if 'Failed to acquire license' in line:
            print(line)
    if 'Client token expired' in log:
        print('CAUSE: automatic license acquisition failed: expired client token (HTTP 401).')
        print('ACTION: obtain a Nios V/m license from SSLC and configure its file in Quartus.')
        print('See UART/fpga/LICENSING.md. A Questa simulation license does not license Nios V hardware.')
    elif 'Could not get NIC ID' in log:
        print('ACTION: run the build in a normal terminal and check the NIC ID in Quartus License Setup.')
    raise SystemExit('REVIEW REQUIRED: Nios V IP license warning; .sof exists but this build is not marked ready for hardware.')
ready.write_text('Compilation, timing and license-log checks passed. Board validation still required.\n')
sources = list((root.parent / 'rtl').rglob('*.v'))
sources += list(root.glob('*.v')) + list(root.glob('*.qsf')) + list(root.glob('*.sdc'))
sources += list((root / 'ip').glob('*.tcl')) + list((root / 'scripts').glob('*.tcl'))
sources += [out / 'de2_115_uart.sof']
(root / 'build/ready_manifest.sha256').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p}\n' for p in sorted(sources)
))
