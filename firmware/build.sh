#!/usr/bin/env bash
set -euo pipefail
firmware_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$firmware_dir/../fpga/scripts/env.sh"
cd "$firmware_dir"
phase="${1:-all}"
target="${2:-echo}"
case "$phase" in prepare|compile|all) ;; *) echo 'Usage: build.sh [prepare|compile|all] [echo|selftest|scope]' >&2; exit 2;; esac
case "$target" in
    echo) app_dir=build/app; elf_name=uart_firmware.elf
          sources="$firmware_dir/main.c,$firmware_dir/dti_uart.c,$firmware_dir/console.c";;
    selftest) app_dir=build/selftest; elf_name=uart_selftest.elf
          sources="$firmware_dir/tests/selftest_main.c,$firmware_dir/tests/uart_selftest.c,$firmware_dir/dti_uart.c,$firmware_dir/console.c";;
    scope) app_dir=build/scope; elf_name=uart_scope.elf
          sources="$firmware_dir/examples/scope_main.c,$firmware_dir/dti_uart.c";;
    *) echo 'Target must be echo, selftest or scope.' >&2; exit 2;;
esac
mkdir -p build/logs
if [[ "$target" == echo ]]; then rm -f build/ready_manifest.sha256; fi
if [[ "$target" == scope ]]; then rm -f build/scope_manifest.sha256; fi
run_logged() {
    local log="$1"; shift
    "$@" > "$log" 2>&1 || { tail -50 "$log"; return 1; }
    if grep -Eq '(^| )Error:|CMake Error|error:' "$log"; then tail -50 "$log"; return 1; fi
}
if [[ "$phase" != compile ]]; then
    test -s ../fpga/uart_soc.sopcinfo || { echo 'Run FPGA build.sh generate first.' >&2; exit 1; }
    run_logged build/logs/bsp.log env -u DISPLAY JAVA_TOOL_OPTIONS=-Djava.awt.headless=true \
        niosv-bsp -c -t=hal -s=../fpga/uart_soc.sopcinfo -i=cpu -x=bsp_settings.tcl build/bsp/settings.bsp
    test -s build/bsp/system.h
    run_logged "build/logs/${target}_app_generate.log" env -u DISPLAY JAVA_TOOL_OPTIONS=-Djava.awt.headless=true \
        niosv-app "-a=$app_dir" -b=build/bsp "-s=$sources" \
        "-i=$firmware_dir" "-e=$elf_name"
    test -s "$app_dir/CMakeLists.txt"
    echo 'PASS BSP and application CMake generation'
fi
if [[ "$phase" != prepare ]]; then
    for tool in riscv32-unknown-elf-gcc riscv32-unknown-elf-g++ cmake make; do
        command -v "$tool" >/dev/null || { echo "Missing $tool. Install RiscFree or set UART_RISCFREE_ROOT." >&2; exit 1; }
    done
    run_logged "build/logs/${target}_cmake.log" cmake -S "$app_dir" -B "$app_dir/build" -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS='-Wall -Wextra'
    run_logged "build/logs/${target}_compile.log" cmake --build "$app_dir/build" --parallel 4
    test -s "$app_dir/build/$elf_name"
    test -s "$app_dir/build/ram.hex"
    riscv32-unknown-elf-size "$app_dir/build/$elf_name" | tee "build/logs/${target}_size.log"
    if [[ "$target" == echo ]]; then
        sha256sum "$firmware_dir"/*.c "$firmware_dir"/*.h "$firmware_dir"/bsp_settings.tcl \
            "$firmware_dir"/build/bsp/system.h "$firmware_dir"/build/app/build/uart_firmware.elf \
            > build/ready_manifest.sha256
    fi
    if [[ "$target" == scope ]]; then
        sha256sum "$firmware_dir"/examples/scope_main.c "$firmware_dir"/dti_uart.c \
            "$firmware_dir"/dti_uart.h "$firmware_dir"/uart_platform.h \
            "$firmware_dir"/bsp_settings.tcl "$firmware_dir"/build/bsp/system.h \
            "$firmware_dir/$app_dir/build/$elf_name" > build/scope_manifest.sha256
    fi
    echo "PASS RISC-V $target firmware ELF and HEX build"
fi
