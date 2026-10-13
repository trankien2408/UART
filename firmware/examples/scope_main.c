// Do UART TX tren oscilloscope: gui "hello", cho 100 ms, lap lai.
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"

#define DELAY_MS 100u
#define TX_TIMEOUT_CYCLES ((uint32_t)ALT_CPU_FREQ / 10u)

static void delay_ms(uint32_t ms)
{
    // mtime tang theo clock CPU. Phep tru unsigned xu ly duoc tran 32 bit.
    // Cho tung ms de khong nhan so chu ky voi mot khoang tre lon.
    while (ms--) {
        uint32_t start = uart_cycles();
        while ((uint32_t)(uart_cycles() - start) < (uint32_t)ALT_CPU_FREQ / 1000u) {
        }
    }
}

static void stop_on_error(void)
{
    uart_mmio_write(CONTROL_BASE, 8u); // LEDG[1] sang khi loi.
    for (;;) {
    }
}

int main(void)
{
    static const char message[] = "hello";
    dti_uart uart;
    uart_mmio_write(CONTROL_BASE, 0u); // TX ra GPIO; tat loopback va CTS.

    if (uart_mmio_read(SYSID_BASE) != 0x55415254u ||
        dti_init(&uart, UART_BASE, TX_TIMEOUT_CYCLES) != DTI_OK ||
        dti_configure(&uart, 8, 1, DTI_PARITY_NONE) != DTI_OK) {
        stop_on_error();
    }

    uart_mmio_write(CONTROL_BASE, 4u); // LEDG[0]: san sang.
    for (;;) {
        // Gui tung ky tu, khong gui byte ket thuc chuoi '\0' hay CR/LF.
        for (unsigned i = 0; i < sizeof(message) - 1u; ++i) {
            if (dti_send(&uart, (uint8_t)message[i]) != DTI_OK) {
                stop_on_error();
            }
        }
        delay_ms(DELAY_MS); // Cho sau khi TX gui xong ca chuoi.
    }
}
