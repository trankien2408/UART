#include <assert.h>
#include <stdio.h>
#include "uart_irq.h"
#include "uart_platform.h"
#define BASE 0x21000u
static uint32_t mask, sticky, frame_sticky;
static unsigned hw_head,hw_tail,locks,registered,fail_register;
static uint16_t hw[2048];
static uint32_t sources(void) {
    return (hw_head!=hw_tail ? DTI_IRQ_RX : 0u)|DTI_IRQ_TX_DONE|
           (sticky ? DTI_IRQ_OVERRUN : 0u) |
           (frame_sticky ? DTI_IRQ_FRAME : 0u);
}
uint32_t uart_cycles(void) { return 0; }
uint32_t uart_irq_lock(void) { unsigned state=locks;locks=1;return state; }
void uart_irq_unlock(uint32_t state) { locks=state; }
int uart_irq_register(void (*fn)(void *),void *ctx) {
    assert(fn==uart_irq_handler && ctx==0);registered++;return fail_register ? -1 : 0;
}
uint32_t uart_mmio_read(uintptr_t a) {
    switch(a-BASE) {
    case DTI_INT_ENABLE:return mask;
    case DTI_INT_STATUS:return sources();
    case DTI_STATUS:return DTI_TX_DONE | (hw_head!=hw_tail ? DTI_RX_DONE : 0u) |
         (hw_head!=hw_tail && (hw[hw_tail]&256) ? DTI_PARITY_ERROR : 0u);
    case DTI_RX:assert(hw_head!=hw_tail);return hw[hw_tail++]&255;
    default:assert(0);return 0;
    }
}
void uart_mmio_write(uintptr_t a,uint32_t v) {
    switch(a-BASE) {
    case DTI_INT_ENABLE:mask=v;return;
    case DTI_FIFO_STATUS:
        assert(v==DTI_RX_OVERRUN || v==DTI_RX_FRAME_ERROR);
        if (v&DTI_RX_OVERRUN) sticky=0;
        if (v&DTI_RX_FRAME_ERROR) frame_sticky=0;
        return;
    default:assert(0);
    }
}
static void push(unsigned n) { for(unsigned i=0;i<n;i++) { unsigned k=hw_head;hw[hw_head++]=(uint16_t)((k&255)|((k%2)*256)); } }
int main(void) {
    dti_uart dev;assert(dti_init(&dev,BASE,100)==DTI_OK);
    assert(uart_irq_init(&dev)==DTI_OK && registered==1 && mask==13);
    frame_sticky=1;uart_irq_handler(0);
    assert(!frame_sticky && mask==13 && !uart_irq_faults());
    assert(uart_irq_take_rx_errors()==UART_RX_ERROR_FRAME);
    assert(uart_irq_take_rx_errors()==0); // Main acknowledgement is one-shot.
    uint8_t byte=0;
    assert(uart_irq_receive(0)==DTI_INVALID && uart_irq_receive(&byte)==DTI_AGAIN);
    // ISR budget is 16; pending RX survives and is handled next entry.
    push(24);uart_irq_handler(0);assert(hw_tail==16);
    uart_irq_handler(0);assert(hw_tail==24);
    for(unsigned i=0;i<24;i++) {
        assert(uart_irq_receive(&byte)==(i%2 ? DTI_PARITY : DTI_OK));assert(byte==i);
    }
    assert(uart_irq_rx_empty() && !uart_irq_faults());
    // Repeat enough to wrap software ring pointers several times.
    for(unsigned r=0;r<80;r++) {
        push(16);uart_irq_handler(0);
        for(unsigned i=0;i<16;i++)assert(uart_irq_receive(&byte)==((i%2) ? DTI_PARITY : DTI_OK));
    }
    uart_irq_tx_arm();assert(mask==15 && !uart_irq_tx_complete());
    uart_irq_handler(0);assert(mask==13 && uart_irq_tx_complete() && !uart_irq_tx_complete());
    // Queue capacity is 511 entries. Overflow is sticky and masks the peripheral.
    for(unsigned r=0;r<32;r++){push(16);uart_irq_handler(0);}
    assert(uart_irq_faults()==UART_FAULT_SW_OVERRUN && mask==0);
    for(unsigned i=0;i<511;i++)assert(uart_irq_receive(&byte)!=DTI_AGAIN);
    assert(uart_irq_receive(&byte)==DTI_AGAIN);
    hw_head=hw_tail=0;assert(uart_irq_init(&dev)==DTI_OK);
    sticky=1;uart_irq_tx_arm();uart_irq_handler(0);
    assert(uart_irq_faults()==UART_FAULT_HW_OVERRUN && !sticky && !mask);
    assert(uart_irq_tx_complete());
    fail_register=1;assert(uart_irq_init(&dev)==DTI_INVALID && mask==0);
    puts("PASS test_irq: real ISR, framing event/W1C/ack, 16-byte budget, parity, ring wrap/overflow, TX level masking, hardware overrun, registration failure");
}
