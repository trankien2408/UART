#include "system.h"
#include "uart_platform.h"
#include "console.h"

#define JTAG_DATA    0u
#define JTAG_CONTROL 4u
#define TX_BUF_SIZE  512u
#define BYTES_PER_POLL 16u

static uint8_t tx_buf[TX_BUF_SIZE];
static unsigned tx_head, tx_tail, tx_count;

void console_init(void)
{
    tx_head = tx_tail = tx_count = 0;
    uart_mmio_write(JTAG_UART_BASE + JTAG_CONTROL, 0); // Tat interrupt.
}

void console_send_byte(uint8_t byte)
{
    (void)console_write(&byte, 1u);
}

int console_write(const uint8_t *data, unsigned length)
{
    if (length > TX_BUF_SIZE - tx_count) return -1;
    for (unsigned i = 0; i < length; ++i) {
        tx_buf[tx_head] = data[i];
        tx_head = (tx_head + 1u) % TX_BUF_SIZE;
        tx_count++;
    }
    return 0;
}

void console_text(const char *text)
{
    while (*text) {
        console_send_byte((uint8_t)*text++);
    }
}

void console_echo(uint8_t byte)
{
    const char hex[] = "0123456789ABCDEF";
    char line[] = "RX=0x00 TX=0x00\r\n";
    line[5] = line[13] = hex[byte >> 4];
    line[6] = line[14] = hex[byte & 15u];
    console_text(line);
}

int console_try_receive(uint8_t *byte)
{
    if (!byte) return -1;
    uint32_t val = uart_mmio_read(JTAG_UART_BASE + JTAG_DATA);
    if (val & (1u << 15)) { // Bit 15: RVALID
        *byte = (uint8_t)(val & 0xFFu);
        return 0; // Doc du lieu thanh cong
    }
    return -1; // Khong co du lieu
}

void console_poll(void)
{
    uint32_t space = uart_mmio_read(JTAG_UART_BASE + JTAG_CONTROL) >> 16;
    for (unsigned i = 0; i < BYTES_PER_POLL && tx_count > 0 && space > 0; i++) {
        uart_mmio_write(JTAG_UART_BASE + JTAG_DATA, tx_buf[tx_tail]);
        tx_tail = (tx_tail + 1u) % TX_BUF_SIZE;
        tx_count--;
        space--;
    }
}
