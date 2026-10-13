#ifndef UART_CONSOLE_H
#define UART_CONSOLE_H
#include <stdint.h>

void console_init(void);
void console_text(const char *text);
void console_send_byte(uint8_t byte);
int console_try_receive(uint8_t *byte);
void console_echo(uint8_t byte);
void console_poll(void);
#endif
