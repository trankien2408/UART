#ifndef UART_PLATFORM_H
#define UART_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#ifdef UART_HOST_TEST
uint32_t uart_mmio_read(uintptr_t address);
void uart_mmio_write(uintptr_t address, uint32_t value);
uint32_t uart_cycles(void);
#else
#include "io.h"
#include "system.h"
#if !defined(ALT_CPU_MTIME_OFFSET) || ALT_CPU_MTIME_OFFSET == 0xffffffff
#error "UART timeout requires the Nios V timer agent connected to the data bus"
#endif
static inline uint32_t uart_mmio_read(uintptr_t address)
{
    return IORD_32DIRECT(address, 0);
}
static inline void uart_mmio_write(uintptr_t address, uint32_t value)
{
    IOWR_32DIRECT(address, 0, value);
}
static inline uint32_t uart_cycles(void)
{
    // Nios V/m hien tai khong ho tro CSR mcycle. mtime tang moi clock CPU.
    // Chi doc 32 bit thap: timeout dung phep tru uint32_t, an toan qua wrap.
    return IORD_32DIRECT(ALT_CPU_MTIME_OFFSET, 0);
}
#endif
#endif
