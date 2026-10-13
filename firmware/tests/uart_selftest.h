#ifndef UART_SELFTEST_H
#define UART_SELFTEST_H
#include "dti_uart.h"
// Requires TX-to-RX loopback, CTS asserted, RX drained, and no external traffic.
int uart_loopback_selftest(const dti_uart *dev, unsigned *frames_checked);
#endif
