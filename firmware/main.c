#include <stdint.h>
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"
#include "console.h"

#define LED_READY       4u
#define LED_ERROR       8u
#define EXPECTED_SYSID  0x55415254u
#define TX_TIMEOUT     ((uint32_t)ALT_CPU_FREQ / 10u)
#define QUEUE_SIZE     512u
#define LINE_SIZE      120u // So byte toi da truoc Enter (khong tinh CR/LF).

typedef struct {
    uint8_t data[LINE_SIZE];
    unsigned length;
    int skip_lf, discard;
} input_line;

static dti_uart uart;
static uint8_t queue[QUEUE_SIZE];
static unsigned head, tail, count;
static int transmitting, failed;
static uint32_t tx_started, leds;
static input_line uart_line, jtag_line;

static void report_error(const char *message, int fatal)
{
    leds |= LED_ERROR;
    uart_mmio_write(CONTROL_BASE, leds);
    console_text(message);
    if (fatal) failed = 1;
}

// Them ca nhom byte hoac khong them gi, tranh mat mot nua CR/LF hay nua dong.
static int queue_write(const uint8_t *data, unsigned length)
{
    if (length > QUEUE_SIZE - count) return -1;
    for (unsigned i = 0; i < length; ++i) {
        queue[head] = data[i];
        head = (head + 1u) % QUEUE_SIZE;
        ++count;
    }
    return 0;
}

static void local_echo(int from_jtag, const uint8_t *data, unsigned length)
{
    int rc = from_jtag ? console_write(data, length) : queue_write(data, length);
    if (rc != 0) report_error("ERROR: local echo queue full\r\n", 0);
}

static void receive_char(input_line *line, uint8_t byte, int from_jtag)
{
    static const uint8_t newline[] = {'\r', '\n'};
    static const uint8_t erase[] = {'\b', ' ', '\b'};
    // Enter co the la CR, LF hoac CR+LF; CR+LF chi ket thuc mot dong.
    if (line->skip_lf && byte == '\n') {
        line->skip_lf = 0;
        return;
    }
    line->skip_lf = 0;
    if (byte == '\r' || byte == '\n') {
        line->skip_lf = byte == '\r';
        local_echo(from_jtag, newline, sizeof(newline));
        if (!line->discard) {
            uint8_t complete[LINE_SIZE + 2u];
            for (unsigned i = 0; i < line->length; ++i) complete[i] = line->data[i];
            complete[line->length] = '\r';
            complete[line->length + 1u] = '\n';
            int rc = from_jtag ? queue_write(complete, line->length + 2u)
                               : console_write(complete, line->length + 2u);
            if (rc != 0) report_error("ERROR: destination queue full; line discarded\r\n", 0);
        }
        line->length = 0;
        line->discard = 0;
    } else if (byte == '\b' || byte == 0x7fu) {
        if (!line->discard && line->length) {
            --line->length;
            local_echo(from_jtag, erase, sizeof(erase));
        }
    } else {
        // Echo chi tai terminal dang go. Chi chuyen sang ben kia khi Enter.
        local_echo(from_jtag, &byte, 1u);
        if (line->discard) return;
        if (line->length == LINE_SIZE) {
            line->discard = 1;
            report_error("ERROR: line exceeds 120 bytes; discarded until Enter\r\n", 0);
        } else {
            line->data[line->length++] = byte;
        }
    }
}

int uart_demo_init(void)
{
    head = tail = count = 0;
    transmitting = failed = 0;
    leds = 0;
    uart_line = (input_line){0};
    jtag_line = (input_line){0};
    uart_mmio_write(CONTROL_BASE, 0);
    console_init();
    if (uart_mmio_read(SYSID_BASE) != EXPECTED_SYSID ||
        dti_init(&uart, UART_BASE, TX_TIMEOUT) != DTI_OK ||
        dti_configure(&uart, 8, 1, DTI_PARITY_NONE) != DTI_OK) {
        report_error("ERROR: init/system ID; reset required\r\n", 1);
        return -1;
    }
    leds = LED_READY;
    uart_mmio_write(CONTROL_BASE, leds);
    console_text("READY: UART chat 115200 8N1; Enter to send\r\n");
    return 0;
}

void uart_demo_poll(void)
{
    console_poll();
    if (failed) return;
    if (transmitting) {
        if (dti_status(&uart) & DTI_TX_DONE) {
            transmitting = 0;
        } else if ((uint32_t)(uart_cycles() - tx_started) >= TX_TIMEOUT) {
            report_error("ERROR: TX timeout; reset required\r\n", 1);
            return;
        }
    }
    if (dti_fifo_status(&uart) & DTI_RX_OVERRUN) {
        // Mat byte co the lam mat ca dau Enter: dung lai, khong gui dong sai.
        report_error("ERROR: RX FIFO overrun; reset required\r\n", 1);
        return;
    }
    uint8_t byte;
    int result = dti_try_receive(&uart, &byte);
    if (result == DTI_PARITY) {
        uart_line.discard = 1;
        report_error("ERROR: RX parity; line discarded until Enter\r\n", 0);
    } else if (result == DTI_OK) {
        receive_char(&uart_line, byte, 0);
    }
    if (console_try_receive(&byte) == 0) receive_char(&jtag_line, byte, 1);
    // Moi lo toi da 16 byte. Doi ca lo phat xong roi nap lo tiep theo;
    // timeout bao trum ca lo va khong bi gia han lien tuc boi du lieu moi.
    if (!transmitting && count) {
        unsigned queued = 0;
        while (queued < 16u && count && dti_try_queue(&uart, queue[tail]) == DTI_OK) {
            tail = (tail + 1u) % QUEUE_SIZE;
            --count;
            ++queued;
        }
        if (queued) {
            tx_started = uart_cycles();
            transmitting = 1;
        }
    }
}

#ifndef UART_DEMO_TEST
int main(void)
{
    (void)uart_demo_init();
    for (;;) uart_demo_poll();
}
#endif
