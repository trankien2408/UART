#!/usr/bin/env bash
# Source this file; override UART_QUARTUS_ROOT / UART_RISCFREE_ROOT if needed.
export UART_QUARTUS_ROOT="${UART_QUARTUS_ROOT:-/home/kien/altera_lite/25.1std}"
export UART_RISCFREE_ROOT="${UART_RISCFREE_ROOT:-$UART_QUARTUS_ROOT/riscfree}"
export QUARTUS_ROOTDIR="$UART_QUARTUS_ROOT/quartus"
export SOPC_KIT_NIOS2="$UART_QUARTUS_ROOT/nios2eds"
# License Nios V/m cap cho may nay; chi ap dung cho cac script cua project.
# Giu nguyen LM_LICENSE_FILE (Questa) va cac duong dan ALTERAD da co.
uart_license_file="${UART_NIOSV_LICENSE_FILE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)/LR-199530_License.dat}"
if [[ -f "$uart_license_file" ]]; then
    case ":${ALTERAD_LICENSE_FILE:-}:" in
        *":$uart_license_file:"*) ;;
        *) export ALTERAD_LICENSE_FILE="$uart_license_file${ALTERAD_LICENSE_FILE:+:$ALTERAD_LICENSE_FILE}" ;;
    esac
fi
unset uart_license_file
export PATH="$UART_QUARTUS_ROOT/quartus/bin:$UART_QUARTUS_ROOT/quartus/linux64:$UART_QUARTUS_ROOT/quartus/sopc_builder/bin:$UART_QUARTUS_ROOT/niosv/bin:$UART_RISCFREE_ROOT/toolchain/riscv32-unknown-elf/bin:$UART_RISCFREE_ROOT/build_tools/cmake/bin:$UART_RISCFREE_ROOT/build_tools/bin:$UART_RISCFREE_ROOT/debugger/gdbserver-riscv:$PATH"
