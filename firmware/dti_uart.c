#include "dti_uart.h"
#include "uart_platform.h"
int dti_init(dti_uart *dev, uintptr_t base, uint32_t timeout_cycles)
{
    if (!dev || (base & 3u) || !timeout_cycles || timeout_cycles >= 0x80000000u)
        return DTI_INVALID;
    dev->base=base;
    dev->timeout_cycles=timeout_cycles;
    return DTI_OK;
}
uint32_t dti_status(const dti_uart *dev)
{
    return uart_mmio_read(dev->base + DTI_STATUS);
}
int dti_wait_tx(const dti_uart *dev)
{
    uint32_t start=uart_cycles();
    do {
        if (dti_status(dev) & DTI_TX_DONE) return DTI_OK;
    } while ((uint32_t)(uart_cycles()-start) < dev->timeout_cycles);
    return DTI_TIMEOUT;
}
int dti_configure(const dti_uart *dev, unsigned bits, unsigned stops, enum dti_parity parity)
{
    // CFG selects frame format; runtime baud uses SHADOW/APPLY separately.
    if (bits<5 || bits>8 || stops<1 || stops>2 ||
        (parity!=DTI_PARITY_NONE && parity!=DTI_PARITY_ODD && parity!=DTI_PARITY_EVEN))
        return DTI_INVALID;
    int rc=dti_wait_tx(dev);
    if (rc!=DTI_OK) return rc;
    uint32_t cfg=(bits-5u)|((stops-1u)<<2);
    if (parity!=DTI_PARITY_NONE) cfg |= 8u;
    if (parity==DTI_PARITY_EVEN) cfg |= 16u;
    uart_mmio_write(dev->base + DTI_CFG, cfg);
    return DTI_OK;
}
uint32_t dti_fifo_status(const dti_uart *dev)
{
    return uart_mmio_read(dev->base + DTI_FIFO_STATUS);
}
void dti_clear_overrun(const dti_uart *dev)
{
    uart_mmio_write(dev->base + DTI_FIFO_STATUS, DTI_RX_OVERRUN);
}
void dti_clear_frame_error(const dti_uart *dev)
{
    uart_mmio_write(dev->base + DTI_FIFO_STATUS, DTI_RX_FRAME_ERROR);
}
int dti_try_queue(const dti_uart *dev, uint8_t byte)
{
    if (dti_fifo_status(dev) & DTI_TX_FULL) return DTI_AGAIN;
    uart_mmio_write(dev->base + DTI_TX, byte);
    uart_mmio_write(dev->base + DTI_CTRL, 1u);
    return DTI_OK;
}
int dti_try_send(const dti_uart *dev, uint8_t byte)
{
    // Khong cho TX: chua san sang thi tra DTI_AGAIN de main phuc vu RX.
    if (!(dti_status(dev) & DTI_TX_DONE)) return DTI_AGAIN;
    uart_mmio_write(dev->base + DTI_TX, byte);
    // Ghi START mot lan; phan cung tu xoa khi TX nhan lenh.
    uart_mmio_write(dev->base + DTI_CTRL, 1u);
    return DTI_OK;
}
int dti_send(const dti_uart *dev, uint8_t byte)
{
    int rc=dti_wait_tx(dev);
    if (rc!=DTI_OK) return rc;
    rc=dti_try_send(dev,byte);
    if (rc!=DTI_OK) return rc;
    return dti_wait_tx(dev);
}
int dti_try_receive(const dti_uart *dev, uint8_t *byte)
{
    if (!byte) return DTI_INVALID;
    uint32_t status=dti_status(dev);
    // Bat buoc kiem tra RX_DONE: doc RX rong se giu bus APB cho vo han.
    if (!(status & DTI_RX_DONE)) return DTI_AGAIN;
    *byte=(uint8_t)uart_mmio_read(dev->base + DTI_RX);
    // Dung parity cua byte vua doc; sau khi pop, status thuoc byte ke tiep.
    return (status & DTI_PARITY_ERROR) ? DTI_PARITY : DTI_OK;
}
int dti_receive(const dti_uart *dev, uint8_t *byte)
{
    if (!byte) return DTI_INVALID;
    uint32_t start=uart_cycles();
    do {
        int rc=dti_try_receive(dev,byte);
        if (rc!=DTI_AGAIN) return rc;
    } while ((uint32_t)(uart_cycles()-start) < dev->timeout_cycles);
    return DTI_TIMEOUT;
}

int dti_baud_divider(uint32_t clock_hz, uint32_t baud, uint16_t *divider, uint32_t *actual)
{
    if (!clock_hz || !baud || !divider) return DTI_INVALID;
    uint64_t target = (uint64_t)baud * 16u;
    uint64_t div = ((uint64_t)clock_hz + target/2u) / target;
    if (!div || div > 65535u) return DTI_INVALID;
    uint64_t product = target * div;
    uint64_t diff = product > clock_hz ? product-clock_hz : clock_hz-product;
    if (diff * 100u > product * 2u) return DTI_INVALID;
    *divider = (uint16_t)div;
    if (actual) *actual = (uint32_t)(((uint64_t)clock_hz + div*8u)/(div*16u));
    return DTI_OK;
}
int dti_set_baud(const dti_uart *dev, uint32_t clock_hz, uint32_t baud, uint32_t *actual)
{
    uint16_t div;
    uint32_t rate;
    if (dti_baud_divider(clock_hz, baud, &div, &rate)!=DTI_OK) return DTI_INVALID;
    uart_mmio_write(dev->base + DTI_BAUD_SHADOW, div);
    uint32_t start = uart_cycles();
    do {
        if (!(uart_mmio_read(dev->base + DTI_BAUD_CONTROL) & DTI_BAUD_BUSY)) {
            uart_mmio_write(dev->base + DTI_BAUD_CONTROL, DTI_BAUD_REJECTED | DTI_BAUD_APPLY);
            uint32_t status = uart_mmio_read(dev->base + DTI_BAUD_CONTROL);
            if (!(status & DTI_BAUD_REJECTED) &&
                uart_mmio_read(dev->base + DTI_BAUD_ACTIVE)==div) {
                if (actual) *actual=rate;
                return DTI_OK;
            }
        }
    } while ((uint32_t)(uart_cycles()-start) < dev->timeout_cycles);
    return DTI_TIMEOUT;
}
