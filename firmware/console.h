#ifndef UART_CONSOLE_H
#define UART_CONSOLE_H
#include <stdint.h>

void console_init(void);
void console_text(const char *text);
// Them nguyen nhom byte, tra -1 neu khong du cho (khong gui nua dong).
int console_write(const uint8_t *data, unsigned length);
int console_try_receive(uint8_t *byte);
void console_poll(void);
#endif
