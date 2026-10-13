#ifndef DTI_UART_DRIVER_H
#define DTI_UART_DRIVER_H
#include <stdint.h>
#include <stddef.h>
enum {
    DTI_TX=0x00, DTI_CFG=0x04, DTI_CTRL=0x08, DTI_STATUS=0x0c, DTI_RX=0x10,
    DTI_TX_DONE=1, DTI_RX_DONE=2, DTI_PARITY_ERROR=4
};
enum dti_parity { DTI_PARITY_NONE, DTI_PARITY_ODD, DTI_PARITY_EVEN };
enum dti_result { DTI_OK=0, DTI_AGAIN=1, DTI_TIMEOUT=-1, DTI_INVALID=-2, DTI_PARITY=-3 };
typedef struct { uintptr_t base; uint32_t timeout_cycles; } dti_uart;
// Single owner only: ISR/second task must not access these registers concurrently.
// Timeout must be in (0, 2^31); timeout never cancels an already queued TX.
int dti_init(dti_uart *dev, uintptr_t base, uint32_t timeout_cycles);
uint32_t dti_status(const dti_uart *dev);
int dti_wait_tx(const dti_uart *dev);
// Peer must be idle when changing frame format (there is no RX-busy status bit).
int dti_configure(const dti_uart *dev, unsigned bits, unsigned stops, enum dti_parity parity);
int dti_try_send(const dti_uart *dev, uint8_t byte);
int dti_send(const dti_uart *dev, uint8_t byte);
// Parity-error return still provides and consumes the received byte.
int dti_try_receive(const dti_uart *dev, uint8_t *byte);
int dti_receive(const dti_uart *dev, uint8_t *byte);
#endif
