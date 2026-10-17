#ifndef DTI_UART_DRIVER_H
#define DTI_UART_DRIVER_H
#include <stdint.h>
#include <stddef.h>
enum {
    DTI_TX=0x00, DTI_CFG=0x04, DTI_CTRL=0x08, DTI_STATUS=0x0c, DTI_RX=0x10,
    DTI_FIFO_STATUS=0x14,
    DTI_BAUD_SHADOW=0x18, DTI_BAUD_ACTIVE=0x1c, DTI_BAUD_CONTROL=0x20,
    DTI_INT_ENABLE=0x24, DTI_INT_STATUS=0x28,
    DTI_BAUD_BUSY=1, DTI_BAUD_REJECTED=2, DTI_BAUD_APPLY=4, DTI_BAUD_DIRTY=8,
    DTI_IRQ_RX=1, DTI_IRQ_TX_DONE=2, DTI_IRQ_OVERRUN=4, DTI_IRQ_FRAME=8,
    DTI_TX_FULL=1, DTI_TX_EMPTY=2, DTI_RX_FULL=4, DTI_RX_EMPTY=8, DTI_RX_OVERRUN=16,
    DTI_RX_FRAME_ERROR=32,
    DTI_TX_DONE=1, DTI_RX_DONE=2, DTI_PARITY_ERROR=4
};
enum dti_parity { DTI_PARITY_NONE, DTI_PARITY_ODD, DTI_PARITY_EVEN };
enum dti_result { DTI_OK=0, DTI_AGAIN=1, DTI_TIMEOUT=-1, DTI_INVALID=-2, DTI_PARITY=-3 };
typedef struct { uintptr_t base; uint32_t timeout_cycles; } dti_uart;
// With the IRQ driver, only ISR pops RX and only main enqueues TX.
// Protect shared control-register updates against ISR/task interleaving.
// Timeout must be in (0, 2^31); timeout never cancels an already queued TX.
int dti_init(dti_uart *dev, uintptr_t base, uint32_t timeout_cycles);
uint32_t dti_status(const dti_uart *dev);
int dti_wait_tx(const dti_uart *dev);
// Peer must be idle when changing frame format (there is no RX-busy status bit).
int dti_configure(const dti_uart *dev, unsigned bits, unsigned stops, enum dti_parity parity);
// Queue without waiting for the active frame; AGAIN means TX FIFO full.
int dti_try_queue(const dti_uart *dev, uint8_t byte);
uint32_t dti_fifo_status(const dti_uart *dev);
void dti_clear_overrun(const dti_uart *dev);
void dti_clear_frame_error(const dti_uart *dev);
// Clock is the UART system clock, not the CPU instruction rate.
// Round divider to nearest; reject >2% baud error, use 64-bit intermediates.
int dti_baud_divider(uint32_t clock_hz, uint32_t baud, uint16_t *divider, uint32_t *actual);
int dti_set_baud(const dti_uart *dev, uint32_t clock_hz, uint32_t baud, uint32_t *actual);
int dti_try_send(const dti_uart *dev, uint8_t byte);
int dti_send(const dti_uart *dev, uint8_t byte);
// Parity-error return still provides and consumes the received byte.
int dti_try_receive(const dti_uart *dev, uint8_t *byte);
int dti_receive(const dti_uart *dev, uint8_t *byte);
#endif
