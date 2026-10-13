#!/usr/bin/env bash
set -euo pipefail
firmware_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$firmware_dir"
mkdir -p build/tests
gcc -std=c11 -Wall -Wextra -Werror -Wpedantic -DUART_HOST_TEST \
    -fsanitize=undefined -g -I. dti_uart.c tests/test_driver.c -o build/tests/test_driver
build/tests/test_driver | tee build/tests/driver.log
gcc -std=c11 -Wall -Wextra -Werror -Wpedantic -DUART_HOST_TEST \
    -I. -Ibuild/bsp -fsyntax-only main.c console.c tests/uart_selftest.c tests/selftest_main.c dti_uart.c
gcc -std=c11 -Wall -Wextra -Werror -Wpedantic -DUART_HOST_TEST -DUART_DEMO_TEST \
    -fsanitize=undefined -g -I. -Ibuild/bsp main.c console.c dti_uart.c tests/test_demo.c -o build/tests/test_demo
build/tests/test_demo | tee build/tests/demo.log
echo 'PASS firmware host syntax check (not a RISC-V executable)' | tee build/tests/syntax.log
