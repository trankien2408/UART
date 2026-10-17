#ifndef UART_IRQ_H
#define UART_IRQ_H
#include "dti_uart.h"
enum { UART_FAULT_HW_OVERRUN=1, UART_FAULT_SW_OVERRUN=2 };
enum { UART_RX_ERROR_FRAME=1 };
// Single instance. ISR alone pops hardware RX; main alone enqueues hardware TX.
int uart_irq_init(const dti_uart *dev);
void uart_irq_handler(void *context);
int uart_irq_receive(uint8_t *byte);
uint32_t uart_irq_faults(void);
// Recoverable RX error events, coalesced until main acknowledges them.
uint32_t uart_irq_take_rx_errors(void);
void uart_irq_tx_arm(void);
int uart_irq_tx_complete(void);
int uart_irq_rx_empty(void);
#endif
