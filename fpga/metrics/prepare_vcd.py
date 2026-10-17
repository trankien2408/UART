"""Remove only testbench scopes; preserve all values/times in the RTL VCD."""
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('$scope module tb_uart_power $end\n$scope module dut $end', '$scope module uart_avalon $end', 1)
header, data=s.split('$enddefinitions $end',1)
assert header.rstrip().endswith('$upscope $end')
header=header.rstrip()[:-len('$upscope $end')]
(p.parent/'activity_mapped.vcd').write_text(header+'$enddefinitions $end'+data)
