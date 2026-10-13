#include <stdint.h>
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"
#include "console.h"

// PIO CONTROL: bit 0 loopback, bit 1 CTS, bit 2 LED ready, bit 3 LED error.
#define LED_READY       4u
#define LED_ERROR       8u
#define EXPECTED_SYSID  0x55415254u
#define TX_TIMEOUT     ((uint32_t)ALT_CPU_FREQ / 10u) // 100 ms
#define QUEUE_SIZE     256u

static dti_uart uart;
static uint8_t queue[QUEUE_SIZE];
static unsigned head, tail, count;
static int transmitting, failed;
static uint32_t tx_started, leds;

static void report_error(const char *message, int fatal)
{
    leds |= LED_ERROR;
    uart_mmio_write(CONTROL_BASE, leds);
    console_text(message);
    if (fatal) failed = 1;
}

// Khoi tao mot lan sau reset. Baud 115200 da duoc dat trong RTL.
int uart_demo_init(void)
{
    head = tail = count = 0;
    transmitting = failed = 0;
    leds = 0;
    uart_mmio_write(CONTROL_BASE, 0); // UART noi ngoai, khong dung CTS.
    console_init();

    if (uart_mmio_read(SYSID_BASE) != EXPECTED_SYSID ||
        dti_init(&uart, UART_BASE, TX_TIMEOUT) != DTI_OK ||
        dti_configure(&uart, 8, 1, DTI_PARITY_NONE) != DTI_OK) {
        report_error("ERROR: init/system ID; reset required\r\n", 1);
        return -1;
    }

    leds = LED_READY;
    uart_mmio_write(CONTROL_BASE, leds);
    console_text("READY: UART echo 115200 8N1\r\n");
    return 0;
}

// Moi lan goi chi xu ly viec dang san sang; khong cho terminal hay UART.
void uart_demo_poll(void)
{
    console_poll();
    if (failed) return;

    // 1. Chi bao TX thanh cong sau khi phan cung da phat xong byte.
    if (transmitting) {
        if (dti_status(&uart) & DTI_TX_DONE) {
            tail = (tail + 1u) % QUEUE_SIZE;
            count--;
            transmitting = 0;
        } else if ((uint32_t)(uart_cycles() - tx_started) >= TX_TIMEOUT) {
            report_error("ERROR: TX timeout; reset required\r\n", 1);
            return;
        }
    }

    // 2. Doc byte tu UART phan cung (PC truyen xuong DE2).
    uint8_t byte;
    int result = dti_try_receive(&uart, &byte);
    if (result == DTI_PARITY) {
        report_error("ERROR: RX parity; byte discarded\r\n", 0);
    } else if (result == DTI_OK) {
        if (count < QUEUE_SIZE) {
            queue[head] = byte;
            head = (head + 1u) % QUEUE_SIZE;
            count++;
        } else {
            report_error("ERROR: echo queue full; byte discarded\r\n", 0);
        }
        // Chuyen byte nhan duoc tu PC sang Terminal 1 (JTAG) de DE2 hien thi
        console_send_byte(byte);
        if (byte == '\r') {
            console_send_byte('\n');
        }
    }

    // 3. Doc byte tu Terminal 1 JTAG (DE2 truyen sang PC).
    uint8_t jbyte;
    if (console_try_receive(&jbyte) == 0) {
        // Echo ve Terminal 1 de nguoi dung thay ky tu minh go, khong bi lag
        if (jbyte == '\r') {
            console_send_byte('\r');
            console_send_byte('\n');
            if (count + 2u <= QUEUE_SIZE) {
                queue[head] = '\r'; head = (head + 1u) % QUEUE_SIZE; count++;
                queue[head] = '\n'; head = (head + 1u) % QUEUE_SIZE; count++;
            }
        } else if (jbyte == 0x08 || jbyte == 0x7F) { // Backspace
            console_send_byte('\b');
            console_send_byte(' ');
            console_send_byte('\b');
            if (count + 3u <= QUEUE_SIZE) {
                queue[head] = '\b'; head = (head + 1u) % QUEUE_SIZE; count++;
                queue[head] = ' ';  head = (head + 1u) % QUEUE_SIZE; count++;
                queue[head] = '\b'; head = (head + 1u) % QUEUE_SIZE; count++;
            }
        } else {
            console_send_byte(jbyte);
            if (count < QUEUE_SIZE) {
                queue[head] = jbyte;
                head = (head + 1u) % QUEUE_SIZE;
                count++;
            }
        }
    }

    // 4. Gui byte trong queue ra UART phan cung neu dang ranh.
    if (!transmitting && count && dti_try_send(&uart, queue[tail]) == DTI_OK) {
        tx_started = uart_cycles();
        transmitting = 1;
    }
}

#ifndef UART_DEMO_TEST
int main(void)
{
    (void)uart_demo_init();
    for (;;) uart_demo_poll();
}
#endif
