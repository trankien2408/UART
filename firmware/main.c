#include <stdint.h>
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"
#include "console.h"
#include "uart_irq.h"

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
static uint32_t tx_started, leds, tx_timeout;
static input_line uart_line, jtag_line;
static uint32_t pending_baud, baud_requested;
static int rx_corrupt, rx_error_reported;

// JTAG-only command. Normal lines still use Enter-to-send chat.
static int baud_command(const input_line *line)
{
    static const char prefix[] = ":baud ";
    if (line->length < sizeof(prefix)-1u) return 0;
    for (unsigned i=0;i<sizeof(prefix)-1u;++i)
        if (line->data[i]!=(uint8_t)prefix[i]) return 0;
    uint32_t rate=0; int valid=line->length>sizeof(prefix)-1u;
    for (unsigned i=sizeof(prefix)-1u;i<line->length;++i) {
        unsigned digit=line->data[i]-'0';
        if (digit>9u || rate>10000000u) { valid=0; break; }
        rate=rate*10u+digit;
    }
    uint16_t div;
    if (!valid || dti_baud_divider(ALT_CPU_FREQ,rate,&div,0)!=DTI_OK)
        console_text("BAUD: invalid rate or error exceeds 2%\r\n");
    else if ((uart_line.length || uart_line.discard) && !rx_corrupt)
        console_text("BAUD: finish UART input line first\r\n");
    else {
        // A damaged line may have lost Enter. Keep JTAG baud recovery usable.
        if (rx_corrupt) uart_line=(input_line){0};
        pending_baud=rate; baud_requested=uart_cycles();
    }
    return 1;
}
static void console_uint(uint32_t value)
{
    uint8_t digits[10]; unsigned n=0;
    do { digits[n++]=(uint8_t)('0'+value%10u);value/=10u; } while(value);
    while(n) { uint8_t digit=digits[--n];(void)console_write(&digit,1); }
}

static void report_error(const char *message, int fatal)
{
    leds |= LED_ERROR;
    uart_mmio_write(CONTROL_BASE, leds);
    console_text(message);
    if (fatal) { failed = 1; uart_mmio_write(UART_BASE+DTI_INT_ENABLE,0); }
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
    if (!from_jtag && (byte<32u || byte>126u) &&
        byte!='\r' && byte!='\n' && byte!='\b' && byte!=0x7fu) {
        // ASCII chat: show invisible/control bytes, without claiming a bit error.
        if (!rx_error_reported) {
            static const char hex[]="0123456789ABCDEF";
            char marker[]="[UART RX NON-TEXT 0x00; check baud]\r\n";
            marker[sizeof("[UART RX NON-TEXT 0x")-1u]=hex[byte>>4];
            marker[sizeof("[UART RX NON-TEXT 0x")]=hex[byte&15u];
            report_error(marker,0);
        }
        rx_error_reported=1; rx_corrupt=1;
        line->length=0; line->discard=1;
        return;
    }
    if (byte == '\r' || byte == '\n') {
        line->skip_lf = byte == '\r';
        local_echo(from_jtag, newline, sizeof(newline));
        if (!line->discard && !(from_jtag && baud_command(line))) {
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
        if (!from_jtag) { rx_corrupt=0; rx_error_reported=0; }
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
    pending_baud=0; baud_requested=0; tx_timeout=TX_TIMEOUT;
    rx_corrupt=0; rx_error_reported=0;
    uart_line = (input_line){0};
    jtag_line = (input_line){0};
    uart_mmio_write(CONTROL_BASE, 0);
    console_init();
    if (uart_mmio_read(SYSID_BASE) != EXPECTED_SYSID ||
        dti_init(&uart, UART_BASE, TX_TIMEOUT) != DTI_OK ||
        dti_configure(&uart, 8, 1, DTI_PARITY_NONE) != DTI_OK ||
        uart_irq_init(&uart) != DTI_OK) {
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
        if (uart_irq_tx_complete()) {
            transmitting = 0;
        } else if ((uint32_t)(uart_cycles() - tx_started) >= tx_timeout) {
            report_error("ERROR: TX timeout; reset required\r\n", 1);
            return;
        }
    }
    if (uart_irq_take_rx_errors() & UART_RX_ERROR_FRAME) {
        if (!rx_error_reported)
            report_error("[UART RX ERROR: FRAME/BREAK; check baud]\r\n",0);
        rx_error_reported=1; rx_corrupt=1;
        uart_line.length=0; uart_line.discard=1; uart_line.skip_lf=0;
    }
    if (uart_irq_faults()) {
        // Mat byte co the lam mat ca dau Enter: dung lai, khong gui dong sai.
        report_error("ERROR: RX FIFO overrun (hardware/software); reset required\r\n", 1);
        return;
    }
    uint8_t byte;
    int result = uart_irq_receive(&byte);
    if (result == DTI_PARITY) {
        rx_corrupt=1;
        uart_line.discard = 1;
        if (!rx_error_reported)
            report_error("[UART RX ERROR: PARITY; line discarded until Enter]\r\n", 0);
        rx_error_reported=1;
    } else if (result == DTI_OK) {
        receive_char(&uart_line, byte, 0);
    }
    if (!pending_baud && console_try_receive(&byte) == 0) receive_char(&jtag_line, byte, 1);
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
            uart_irq_tx_arm();
        }
    }
    if (pending_baud && (transmitting || count)) baud_requested=uart_cycles();
    if (pending_baud && !transmitting && !count) {
        if (uart_line.length || uart_line.discard) {
            console_text("BAUD: RX activity; change cancelled\r\n"); pending_baud=0;
        } else if ((uint32_t)(uart_cycles()-baud_requested)>=TX_TIMEOUT) {
            console_text("BAUD: busy; unchanged\r\n"); pending_baud=0;
        } else if (uart_irq_rx_empty() && !(dti_status(&uart)&DTI_RX_DONE) &&
                   !(uart_mmio_read(UART_BASE+DTI_BAUD_CONTROL)&DTI_BAUD_BUSY)) {
            // One short, non-waiting transaction sequence under the CPU IRQ lock.
            uint16_t div; uint32_t actual;
            (void)dti_baud_divider(ALT_CPU_FREQ,pending_baud,&div,&actual);
            uint32_t state=uart_irq_lock();
            uint32_t status=DTI_BAUD_REJECTED, active=0;
            // Recheck after locking: ISR may have filled its ring since the outer test.
            if (uart_irq_rx_empty() && !(dti_status(&uart)&DTI_RX_DONE)) {
                uart_mmio_write(UART_BASE+DTI_BAUD_SHADOW,div);
                uart_mmio_write(UART_BASE+DTI_BAUD_CONTROL,DTI_BAUD_REJECTED|DTI_BAUD_APPLY);
                status=uart_mmio_read(UART_BASE+DTI_BAUD_CONTROL);
                active=uart_mmio_read(UART_BASE+DTI_BAUD_ACTIVE);
            }
            uart_irq_unlock(state);
            if (!(status&DTI_BAUD_REJECTED) && active==div) {
                // Allow a complete 16-byte 8N1 batch at low baud, with margin.
                tx_timeout=(uint32_t)(((uint64_t)ALT_CPU_FREQ*320u)/actual)+TX_TIMEOUT;
                console_text("BAUD: requested ");console_uint(pending_baud);
                console_text("; actual ");console_uint(actual);
                console_text("; change picocom baud now\r\n");
                rx_corrupt=0; rx_error_reported=0;
                pending_baud=0;
            }
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
