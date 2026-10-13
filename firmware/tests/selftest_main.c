// Chuong trinh RIENG: kiem tra 24 dinh dang x 8 mau du lieu bang loopback.
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"
#include "uart_selftest.h"
#include "console.h"

int main(void)
{
    dti_uart uart;
    unsigned frames = 0;
    console_init();
    uart_mmio_write(CONTROL_BASE, 1u); // Loopback noi bo, TX ngoai giu idle.
    int result = dti_init(&uart, UART_BASE, (uint32_t)ALT_CPU_FREQ / 10u);
    if (uart_mmio_read(SYSID_BASE) != 0x55415254u) result = DTI_INVALID;
    if (result == DTI_OK) result = uart_loopback_selftest(&uart, &frames);
    int passed = result == DTI_OK && frames == 192u;
    uart_mmio_write(CONTROL_BASE, 1u | (passed ? 4u : 8u));
    console_text(passed ? "SELFTEST PASS: 192 frames\r\n" : "SELFTEST FAIL\r\n");
    for (;;) console_poll(); // Khong tu chuyen sang echo: day la ELF kiem thu.
}
