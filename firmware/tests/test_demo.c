#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "system.h"
#include "dti_uart.h"
#include "uart_platform.h"
#include "console.h"

int uart_demo_init(void);
void uart_demo_poll(void);
static uint32_t status, rx_byte, tx_byte, cfg, control, cycles, sysid;
static uint32_t fifo_errors;
static unsigned starts, rx_reads, space, log_count;
static uint8_t sent[4096];
static int jtag_pending;
static uint8_t jtag_byte;
static char log_data[65536];

uint32_t uart_cycles(void) { return cycles++; }
uint32_t uart_mmio_read(uintptr_t address)
{
    if (address == SYSID_BASE) return sysid;
    if (address == JTAG_UART_BASE + 4u) return space << 16;
    if (address == JTAG_UART_BASE) {
        if (!jtag_pending) return 0;
        jtag_pending = 0;
        return (1u << 15) | jtag_byte;
    }
    if (address == UART_BASE + DTI_FIFO_STATUS) return fifo_errors | ((status & DTI_TX_DONE) ? 0u : DTI_TX_FULL);
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
    fifo_errors = 0;
    status = DTI_TX_DONE;
    rx_byte = tx_byte = cfg = control = cycles = 0;
    starts = rx_reads = log_count = 0;
    space = 64;
    jtag_pending = 0;
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
    assert(strstr(log_data, "READY: UART chat 115200 8N1; Enter to send\r\n"));
    assert(starts == 0 && rx_reads == 0); // Khong gui greeting ra UART.
    log_count = 0; log_data[0] = 0;
}

static void settle(void)
{
    for (unsigned i = 0; i < 1024; ++i) {
        status |= DTI_TX_DONE;
        poll(64);
    }
}
static void input(int jtag, const char *text)
{
    while (*text) {
        if (jtag) { assert(!jtag_pending); jtag_byte=(uint8_t)*text; jtag_pending=1; }
        else receive((uint8_t)*text, 0);
        poll(64);
        settle();
        ++text;
    }
}
static void clear_output(void)
{
    starts=log_count=0;
    log_data[0]=0;
}
static void expect_uart(const char *text)
{
    assert(starts==strlen(text));
    assert(memcmp(sent,text,starts)==0);
}
int main(void)
{
    // Khong chuyen ky tu dang go sang terminal ben kia.
    boot(); input(1,"abc");
    expect_uart(""); assert(strcmp(log_data,"abc")==0);
    input(1,"\r\n");
    expect_uart("abc\r\n"); assert(strcmp(log_data,"abc\r\n")==0);
    boot(); input(0,"abc");
    expect_uart("abc"); assert(log_count==0);
    input(0,"\r\n");
    expect_uart("abc\r\n"); assert(strcmp(log_data,"abc\r\n")==0);

    // Ca hai chieu: CR, LF, CRLF deu tao dung mot CRLF, khong stair-step.
    for (int side=0;side<2;++side) {
        boot(); input(side,"ad\rbc\ncd\r\n");
        expect_uart("ad\r\nbc\r\ncd\r\n");
        assert(strcmp(log_data,"ad\r\nbc\r\ncd\r\n")==0);
        clear_output(); input(side,"\r\n\n");
        expect_uart("\r\n\r\n"); assert(strcmp(log_data,"\r\n\r\n")==0);
        boot(); input(side,"\b\177ab\b\177cd\r");
        // Chieu gui di chi thay dong da sua, khong thay backspace.
        if (side) expect_uart("cd\r\n");
        else assert(strcmp(log_data,"cd\r\n")==0);
        assert(control==4u);
    }
    // Hai bo dem nhap doc lap khi go xen ke.
    boot(); input(1,"left"); input(0,"right");
    clear_output(); input(1,"\n"); expect_uart("left\r\n");
    assert(strcmp(log_data,"\r\n")==0);
    clear_output(); input(0,"\r\n"); expect_uart("\r\n");
    assert(strcmp(log_data,"right\r\n")==0);

    for (int side=0;side<2;++side) {
        char line[121]; memset(line,'x',120); line[120]=0;
        boot(); input(side,line); clear_output(); input(side,"\n");
        if (side) { assert(starts==122); assert(sent[120]=='\r' && sent[121]=='\n'); }
        else { assert(log_count==122); assert(log_data[120]=='\r' && log_data[121]=='\n'); }
        // Qua 120 byte: loai ca dong, khong gui mot tien to bi cat ngan.
        boot(); input(side,line); input(side,"x"); clear_output(); input(side,"\n");
        assert(control==12u);
        if (side) expect_uart(""); else assert(log_count==0);
        clear_output(); input(side,"ok\n");
        if (side) expect_uart("ok\r\n"); else assert(strcmp(log_data,"ok\r\n")==0);
    }

    boot(); input(0,"abc"); receive('x',1); poll(64); settle();
    clear_output(); input(0,"def\n"); assert(log_count==0 && control==12u);
    input(0,"ok\n"); assert(strcmp(log_data,"ok\r\n")==0);

    // TX dung: timeout qua wrap khong duoc lap lai byte.
    boot(); cycles=0xfffffff0u; receive('Z',0); poll(64);
    cycles+=(uint32_t)ALT_CPU_FREQ/5u; poll(64); flush_log();
    assert(control==12u && starts==1 && strstr(log_data,"TX timeout"));
    status|=DTI_TX_DONE; receive('x',0); flush_log(); assert(starts==1 && rx_reads==1);

    // UART TX queue day: khong duoc chen nua dong JTAG.
    boot();
    for(unsigned i=0;i<513;++i) { receive('x',0); poll(64); }
    clear_output();
    jtag_byte='z';jtag_pending=1;poll(64);
    jtag_byte='\n';jtag_pending=1;poll(64);
    assert(starts==0 && control==12u);
    settle(); assert(starts==512);
    assert(strstr(log_data,"destination queue full"));
    for(unsigned i=0;i<starts;++i) assert(sent[i]=='x');

    // JTAG bi chan: van phuc vu UART, dong bi loai nguyen ven neu queue day.
    boot();
    for(unsigned i=0;i<4;++i) {
        for(unsigned j=0;j<120;++j) { receive('q',0); status|=DTI_TX_DONE;poll(0); }
        receive('\n',0);status|=DTI_TX_DONE;poll(0);
        status|=DTI_TX_DONE;poll(0);status|=DTI_TX_DONE;poll(0);
    }
    receive('r',0);status|=DTI_TX_DONE;poll(0);
    receive('\n',0);status|=DTI_TX_DONE;poll(0);
    assert(log_count==0 && !(control&8u));
    settle(); assert(log_count==491); // 4*(120+CRLF) + r+CRLF

    // JTAG queue khong du cho ca dong: khong duoc chen tien to hoac nua CRLF.
    boot();
    uint8_t fill[500]; memset(fill,'X',sizeof(fill));
    assert(console_write(fill,sizeof(fill))==0);
    assert(console_write((const uint8_t *)"abcdefghijklmnop\r\n",18u)==-1);
    settle(); assert(log_count==500);
    for(unsigned i=0;i<log_count;++i) assert(log_data[i]=='X');

    boot(); fifo_errors=DTI_RX_OVERRUN; receive('x',0);poll(64);flush_log();
    assert(control==12u && rx_reads==0 && strstr(log_data,"RX FIFO overrun"));
    fifo_errors=0;poll(64);assert(rx_reads==0); // fatal error needs reset

    reset_model();sysid=0;assert(uart_demo_init()==-1);flush_log();
    assert(control==8u && starts==0 && strstr(log_data,"init/system ID"));
    boot();
    puts("PASS test_demo: bidirectional Enter buffering, CR/LF/CRLF, no blank/staircase lines, backspace, independent inputs, line limit/recovery, parity, TX queue overflow, blocked JTAG, timeout/wrap, bad SYSID/reset");
    return 0;
}
