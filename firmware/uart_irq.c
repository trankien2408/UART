#include "uart_irq.h"
#include "uart_platform.h"
#define RX_SIZE 512u
static const dti_uart *device;
static uint16_t received[RX_SIZE]; // bit 8 is parity, belonging to this byte
static volatile unsigned head, tail;
static volatile uint32_t faults;
static volatile int tx_complete;

int uart_irq_init(const dti_uart *dev)
{
    device=dev;
    uart_mmio_write(dev->base+DTI_INT_ENABLE,0);
    head=tail=0; faults=0; tx_complete=0;
    if (uart_irq_register(uart_irq_handler,0)!=0) return DTI_INVALID;
    uart_mmio_write(dev->base+DTI_INT_ENABLE,DTI_IRQ_RX|DTI_IRQ_OVERRUN);
    return DTI_OK;
}
static void uart_irq_stop(void)
{
    uart_mmio_write(device->base+DTI_INT_ENABLE,0);
}
void uart_irq_handler(void *context)
{
    (void)context;
    uint32_t enabled=uart_mmio_read(device->base+DTI_INT_ENABLE);
    uint32_t pending=enabled & uart_mmio_read(device->base+DTI_INT_STATUS);
    if (pending & DTI_IRQ_OVERRUN) {
        faults |= UART_FAULT_HW_OVERRUN;
        dti_clear_overrun(device);
    }
    if (pending & DTI_IRQ_RX) {
        for (unsigned i=0;i<16u;++i) {
            uint8_t byte;
            int rc=dti_try_receive(device,&byte);
            if (rc==DTI_AGAIN) break;
            unsigned next=(head+1u)%RX_SIZE;
            if (next==tail) faults |= UART_FAULT_SW_OVERRUN;
            else {
                received[head]=(uint16_t)byte | (rc==DTI_PARITY ? 0x100u : 0u);
                head=next;
            }
        }
    }
    if (pending & DTI_IRQ_TX_DONE) {
        // TX_DONE is a level: mask after servicing to avoid an idle IRQ storm.
        uart_mmio_write(device->base+DTI_INT_ENABLE,enabled & ~DTI_IRQ_TX_DONE);
        tx_complete=1;
    }
    if (faults) uart_irq_stop(); // Main reports the error; ISR never prints.
}
int uart_irq_receive(uint8_t *byte)
{
    if (!byte) return DTI_INVALID;
    uint32_t state=uart_irq_lock();
    if (head==tail) { uart_irq_unlock(state); return DTI_AGAIN; }
    uint16_t value=received[tail]; tail=(tail+1u)%RX_SIZE;
    uart_irq_unlock(state);
    *byte=(uint8_t)value;
    return value & 0x100u ? DTI_PARITY : DTI_OK;
}
int uart_irq_rx_empty(void)
{
    uint32_t state=uart_irq_lock(); int empty=head==tail; uart_irq_unlock(state);
    return empty;
}
uint32_t uart_irq_faults(void) { return faults; }
void uart_irq_tx_arm(void)
{
    // Call AFTER enqueue. An already completed frame is still detected by level IRQ.
    uint32_t state=uart_irq_lock();
    tx_complete=0;
    if (faults) { uart_irq_unlock(state); return; }
    uint32_t enabled=uart_mmio_read(device->base+DTI_INT_ENABLE);
    uart_mmio_write(device->base+DTI_INT_ENABLE,enabled | DTI_IRQ_TX_DONE);
    uart_irq_unlock(state);
}
int uart_irq_tx_complete(void)
{
    uint32_t state=uart_irq_lock(); int done=tx_complete;
    tx_complete=0; uart_irq_unlock(state); return done;
}
