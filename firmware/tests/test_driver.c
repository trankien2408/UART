#include <assert.h>
#include <stdio.h>
#include "dti_uart.h"
#include "uart_platform.h"
static uint32_t tick, status, cfg, txdata, rxdata, finish;
static unsigned writes, starts, rx_reads;
static int complete_tx;
#define BASE ((uintptr_t)0x21000u)
uint32_t uart_cycles(void) { tick+=10; return tick; }
uint32_t uart_mmio_read(uintptr_t address)
{
    if(complete_tx && !(status&1) && (int32_t)(tick-finish)>=0) status|=1;
    switch(address-BASE) {
    case DTI_STATUS: return status;
    case DTI_CFG: return cfg;
    case DTI_RX:
        assert(status & DTI_RX_DONE); // empty RX MMIO is forbidden in the driver
        rx_reads++; status &= ~(DTI_RX_DONE|DTI_PARITY_ERROR); return rxdata;
    default: assert(0); return 0;
    }
}
void uart_mmio_write(uintptr_t address,uint32_t value)
{
    writes++;
    switch(address-BASE) {
    case DTI_CFG: assert(status&1); cfg=value; break;
    case DTI_TX: assert(status&1); txdata=value; break;
    case DTI_CTRL: assert(value==1 && (status&1)); status &= ~1u; starts++; finish=tick+40; break;
    default: assert(0);
    }
}
int main(void)
{
    dti_uart dev;
    assert(dti_init(NULL,BASE,100)==DTI_INVALID);
    assert(dti_init(&dev,BASE+1,100)==DTI_INVALID);
    assert(dti_init(&dev,BASE,0)==DTI_INVALID);
    assert(dti_init(&dev,BASE,0x80000000u)==DTI_INVALID);
    assert(dti_init(&dev,BASE,100)==DTI_OK);
    status=1;
    for(unsigned bits=5;bits<=8;bits++) for(unsigned stops=1;stops<=2;stops++) for(unsigned parity=0;parity<3;parity++) {
        assert(dti_configure(&dev,bits,stops,(enum dti_parity)parity)==0);
        assert(cfg==((bits-5)|((stops-1)<<2)|(parity ? 8 : 0)|(parity==2 ? 16 : 0)));
    }
    unsigned before=writes;
    assert(dti_configure(&dev,4,1,DTI_PARITY_NONE)==DTI_INVALID);
    assert(dti_configure(&dev,9,1,DTI_PARITY_NONE)==DTI_INVALID);
    assert(dti_configure(&dev,8,0,DTI_PARITY_NONE)==DTI_INVALID);
    assert(dti_configure(&dev,8,3,DTI_PARITY_NONE)==DTI_INVALID);
    assert(dti_configure(&dev,8,1,(enum dti_parity)-1)==DTI_INVALID);
    assert(writes==before);
    uint8_t byte=0x55;
    assert(dti_try_receive(&dev,&byte)==DTI_AGAIN && rx_reads==0 && byte==0x55);
    assert(dti_receive(&dev,&byte)==DTI_TIMEOUT && rx_reads==0);
    assert(dti_try_receive(&dev,NULL)==DTI_INVALID);
    assert(dti_receive(&dev,NULL)==DTI_INVALID);
    status=7; rxdata=0xda;
    assert(dti_try_receive(&dev,&byte)==DTI_PARITY && byte==0xda && status==1 && rx_reads==1);
    status=3; rxdata=0x35;
    assert(dti_receive(&dev,&byte)==DTI_OK && byte==0x35 && status==1);
    complete_tx=1;
    assert(dti_send(&dev,0xa7)==DTI_OK && txdata==0xa7 && starts==1);
    complete_tx=0;
    assert(dti_send(&dev,0xb8)==DTI_TIMEOUT && starts==2);
    before=writes;
    assert(dti_try_send(&dev,0xcc)==DTI_AGAIN && writes==before);
    assert(dti_send(&dev,0xdd)==DTI_TIMEOUT && starts==2 && writes==before);
    assert(dti_configure(&dev,8,1,DTI_PARITY_NONE)==DTI_TIMEOUT && writes==before);
    // Unsigned elapsed-time calculation must survive 32-bit cycle-counter wrap.
    tick=0xfffffff0u;
    assert(dti_wait_tx(&dev)==DTI_TIMEOUT && tick<200u);
    status=1; complete_tx=1; tick=0xfffffff0u;
    assert(dti_send(&dev,0xee)==DTI_OK && starts==3 && tick<100u);
    puts("PASS test_driver: 24 configs, invalid inputs, nonblocking RX/TX, parity, timeouts, no retransmit, cycle wrap");
    return 0;
}
