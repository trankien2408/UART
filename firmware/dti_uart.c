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
    // CFG chi chon dinh dang frame; baud rate la parameter cua RTL.
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
    // Dung status da luu: doc RX vua xoa ca RX_DONE va PARITY_ERROR.
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
