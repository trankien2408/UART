#include "uart_selftest.h"
int uart_loopback_selftest(const dti_uart *dev, unsigned *frames_checked)
{
    static const uint8_t patterns[]={0,255,85,170,1,128,126,195};
    *frames_checked=0;
    for(unsigned bits=5;bits<=8;bits++) {
        for(unsigned stops=1;stops<=2;stops++) {
            for(unsigned parity=0;parity<3;parity++) {
                int rc=dti_configure(dev,bits,stops,(enum dti_parity)parity);
                if(rc!=DTI_OK) return rc;
                for(unsigned i=0;i<sizeof(patterns);i++) {
                    uint8_t received=0;
                    rc=dti_send(dev,patterns[i]);
                    if(rc!=DTI_OK) return rc;
                    rc=dti_receive(dev,&received);
                    if(rc!=DTI_OK) return rc;
                    if(received!=(patterns[i] & ((1u<<bits)-1u))) return DTI_INVALID;
                    if(dti_status(dev)&(DTI_RX_DONE|DTI_PARITY_ERROR)) return DTI_INVALID;
                    (*frames_checked)++;
                }
            }
        }
    }
    return DTI_OK;
}
