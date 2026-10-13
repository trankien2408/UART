#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"

int uart_demo_init(void);
void uart_demo_poll(void);
static uint32_t status, rx_byte, tx_byte, cfg, control, cycles, sysid;
static unsigned starts, rx_reads, space, log_count;
static uint8_t sent[4096];
static char log_data[65536];

uint32_t uart_cycles(void) { return cycles++; }
uint32_t uart_mmio_read(uintptr_t address)
{
    if (address == SYSID_BASE) return sysid;
    if (address == JTAG_UART_BASE + 4u) return space << 16;
    if (address == JTAG_UART_BASE) return 0; // JTAG RX empty
    if (address == UART_BASE + DTI_STATUS) return status;
    if (address == UART_BASE + DTI_RX) {
        assert(status & DTI_RX_DONE); // Khong doc RX rong: tren RTL se treo bus.
        rx_reads++;
        status &= ~(DTI_RX_DONE | DTI_PARITY_ERROR);
        return rx_byte;
    }
    assert(0);
    return 0;
}
void uart_mmio_write(uintptr_t address, uint32_t value)
{
    if (address == CONTROL_BASE) { control = value; return; }
    if (address == JTAG_UART_BASE + 4u) { assert(value == 0); return; }
    if (address == JTAG_UART_BASE) {
        assert(space && log_count + 1u < sizeof(log_data));
        space--;
        log_data[log_count++] = (char)value;
        log_data[log_count] = 0;
        return;
    }
    assert(status & DTI_TX_DONE);
    if (address == UART_BASE + DTI_CFG) cfg = value;
    else if (address == UART_BASE + DTI_TX) tx_byte = value;
    else if (address == UART_BASE + DTI_CTRL) {
        assert(value == 1u && starts < sizeof(sent));
        sent[starts++] = (uint8_t)tx_byte;
        status &= ~DTI_TX_DONE;
    } else assert(0);
}
static void reset_model(void)
{
    status = DTI_TX_DONE;
    rx_byte = tx_byte = cfg = control = cycles = 0;
    starts = rx_reads = log_count = 0;
    space = 64;
    sysid = 0x55415254u;
    log_data[0] = 0;
}
static void poll(unsigned available)
{
    space = available;
    uart_demo_poll();
    assert(available - space <= 16u); // Log khong chiem CPU qua lau.
}
static void flush_log(void)
{
    for (unsigned i = 0; i < 32; i++) poll(64);
}
static void receive(uint8_t byte, int parity)
{
    assert(!(status & DTI_RX_DONE));
    rx_byte = byte;
    status |= DTI_RX_DONE | (parity ? DTI_PARITY_ERROR : 0u);
}
static void boot(void)
{
    reset_model();
    assert(uart_demo_init() == 0);
    assert(cfg == 3u && control == 4u);
    flush_log();
    assert(strstr(log_data, "READY: UART echo 115200 8N1\r\n"));
    assert(starts == 0 && rx_reads == 0); // Khong gui greeting ra UART.
    log_count = 0; log_data[0] = 0;
}
int main(void)
{
    boot();
    for (unsigned i = 0; i < 768; i++) {
        uint8_t byte = (uint8_t)i;
        receive(byte, 0);
        poll(64);
        assert(starts == i + 1 && sent[i] == byte);
        status |= DTI_TX_DONE;
        flush_log();
        char expected[40];
        if (byte == '\r') {
            expected[0] = '\r'; expected[1] = '\n'; expected[2] = 0;
        } else {
            expected[0] = (char)byte; expected[1] = 0;
        }
        assert(strcmp(log_data, expected) == 0);
        log_count = 0; log_data[0] = 0;
    }
    assert(control == 4u);

    boot();
    for (unsigned i = 0; i < 1024; i++) {
        receive((uint8_t)i, 0);
        poll(0); // Khong co terminal JTAG / FIFO JTAG day.
        status |= DTI_TX_DONE;
        poll(0);
        assert(starts == i + 1 && sent[i] == (uint8_t)i);
    }
    assert(log_count == 0 && control == 4u);
    flush_log(); // Log cu van duoc flush khi terminal doc tro lai.
    assert(log_count > 0);

    boot();
    receive(0x55, 1); poll(64); flush_log();
    assert(starts == 0 && rx_reads == 1 && control == 12u);
    assert(strstr(log_data, "RX parity"));
    receive(0xA5, 0); poll(64);
    assert(starts == 1 && sent[0] == 0xA5); // Loi parity khong dung ung dung.

    boot();
    // TX bi giu: lap day 256 byte, byte thu 257 bi loai, khong ghi de byte cu.
    for (unsigned i = 0; i < 257; i++) {
        receive((uint8_t)i, 0); poll(64);
    }
    assert(starts == 1 && control == 12u && rx_reads == 257);
    for (unsigned i = 0; i < 256; i++) { status |= DTI_TX_DONE; poll(64); }
    assert(starts == 256);
    for (unsigned i = 0; i < 256; i++) assert(sent[i] == (uint8_t)i);
    flush_log();
    assert(memmem(log_data, log_count, "queue full", 10) != NULL);

    boot();
    cycles = 0xfffffff0u;
    receive(0x5A, 0); poll(64);
    cycles += (uint32_t)ALT_CPU_FREQ / 5u; // Qua timeout va tran bo dem 32 bit.
    poll(64); flush_log();
    assert(control == 12u && starts == 1 && memmem(log_data, log_count, "TX timeout", 10) != NULL);
    status |= DTI_TX_DONE;
    receive(0x66, 0); flush_log();
    assert(starts == 1 && rx_reads == 1); // Khong retry byte cu sau timeout.

    reset_model(); sysid = 0;
    assert(uart_demo_init() == -1);
    flush_log();
    assert(control == 8u && starts == 0 && cfg == 0);
    assert(strstr(log_data, "init/system ID"));
    boot(); // Reset khoi phuc duoc ca trang thai loi va hang doi.
    puts("PASS test_demo: 768 exact echoes, 1024 with JTAG blocked, logs after TX_DONE, parity, queue overflow/order, timeout/wrap/no retry, bad SYSID, reset");
    return 0;
}
