// Native C driver + the real Verilog peripheral, coupled using Icarus VPI.
// This tests C/MMIO/RTL together; it does NOT emulate the Nios V instruction set.
#include <vpi_user.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include "dti_uart.h"
#include "uart_selftest.h"
#include "uart_platform.h"
#ifdef UART_ECHO_COSIM
#include "system.h"
int uart_demo_init(void);
void uart_demo_poll(void);
#endif
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed=PTHREAD_COND_INITIALIZER;
static pthread_t cpu_thread;
static atomic_uint clock_cycles;
static int pending, complete, finished, direction, result_code;
static uintptr_t address;
static uint32_t data, result;
static unsigned frames, transactions;
static uint32_t exchange(int write,uintptr_t addr,uint32_t value)
{
    pthread_mutex_lock(&lock);
    direction=write; address=addr; data=value; pending=1; complete=0;
    pthread_cond_broadcast(&changed);
    while(!complete) pthread_cond_wait(&changed,&lock);
    uint32_t answer=result;
    pthread_mutex_unlock(&lock);
    return answer;
}
uint32_t uart_cycles(void) { return atomic_load(&clock_cycles); }
uint32_t uart_mmio_read(uintptr_t addr) { return exchange(0,addr,0); }
void uart_mmio_write(uintptr_t addr,uint32_t value) { (void)exchange(1,addr,value); }
static void *firmware(void *unused)
{
    (void)unused;
#ifdef UART_ECHO_COSIM
    result_code=uart_demo_init();
    if(result_code==0) for(;;) uart_demo_poll();
#else
    dti_uart dev;
    result_code=dti_init(&dev,0x21000,5000000);
    if(result_code==0) result_code=uart_loopback_selftest(&dev,&frames);
#endif
    pthread_mutex_lock(&lock);
    finished=1;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    return NULL;
}
static PLI_INT32 start_cb(PLI_BYTE8 *unused)
{
    (void)unused;
    if(pthread_create(&cpu_thread,NULL,firmware,NULL)!=0) {
        vpi_printf("FAIL firmware_cosim: cannot create firmware thread\n");
        vpi_control(vpiFinish,1);
    }
    return 0;
}
static uint32_t get(vpiHandle handle)
{
    s_vpi_value value={.format=vpiIntVal};
    vpi_get_value(handle,&value);
    return (uint32_t)value.value.integer;
}
static void put(vpiHandle handle,uint32_t value)
{
    s_vpi_value v={.format=vpiIntVal};
    v.value.integer=(PLI_INT32)value;
    vpi_put_value(handle,&v,NULL,vpiNoDelay);
}
static PLI_INT32 tick_cb(PLI_BYTE8 *unused)
{
    (void)unused;
    // args: address, read, write, writedata, byteenable,
    // accepted, readvalid, writevalid, readdata, response, cycles.
    static vpiHandle args[12];
    static int initialized, state;
    if(!initialized) {
        vpiHandle iter=vpi_iterate(vpiArgument,vpi_handle(vpiSysTfCall,NULL));
        for(int i=0;i<11;i++) args[i]=vpi_scan(iter);
#ifdef UART_ECHO_COSIM
        args[11]=vpi_scan(iter); // PIO control: demo ready/error LEDs.
#endif
        vpi_free_object(iter);
        initialized=1;
    }
    atomic_store(&clock_cycles,get(args[10]));
    pthread_mutex_lock(&lock);
    if(state==1 && get(args[5])) {
        put(args[1],0); put(args[2],0); state=2;
    }
    if(state==2 && (get(args[6]) || get(args[7]))) {
        if(get(args[9]) || get(args[7])!=(unsigned)direction) {
            vpi_printf("FAIL firmware_cosim: Avalon error/response direction\n");
            pthread_mutex_unlock(&lock); vpi_control(vpiFinish,1); return 0;
        }
        result=get(args[8]); complete=1; state=0; transactions++;
        pthread_cond_broadcast(&changed);
    }
    if(state==0) {
        // Only wait while the CPU is executing native C between MMIO accesses.
        // Simulation continues freely while an RTL bus transaction is in flight.
        while(!pending && !finished) pthread_cond_wait(&changed,&lock);
        if(finished) {
            pthread_mutex_unlock(&lock);
            pthread_join(cpu_thread,NULL);
            vpi_printf("%s firmware_cosim: frames=%u transactions=%u cycles=%u rc=%d\n",
                result_code==0 && frames==192 ? "PASS" : "FAIL",
                frames,transactions,atomic_load(&clock_cycles),result_code);
            vpi_control(vpiFinish,result_code!=0); return 0;
        }
#ifdef UART_ECHO_COSIM
        // CPU is native C; JTAG/PIO/SYSID are modeled here. UART bus is real RTL.
        // Every modeled MMIO also advances simulation, including fatal-error loops.
        if(address<0x21000 || address>=0x22000) {
            int valid=1;
            result=0;
            if(!direction && address==SYSID_BASE) result=0x55415254u;
            else if(!direction && address==JTAG_UART_BASE) result=0; // JTAG RX empty
            else if(!direction && address==JTAG_UART_BASE+4u) result=0; // JTAG full
            else if(direction && address==JTAG_UART_BASE) {} // drop JTAG TX
            else if(direction && address==JTAG_UART_BASE+4u && data==0) {}
            else if(direction && address==CONTROL_BASE) put(args[11],data);
            else valid=0;
            if(!valid) {
                vpi_printf("FAIL firmware_echo_cosim: invalid MMIO %x\n",(unsigned)address);
                pthread_mutex_unlock(&lock); vpi_control(vpiFinish,1); return 0;
            }
            pending=0; complete=1; transactions++;
            pthread_cond_broadcast(&changed);
            pthread_mutex_unlock(&lock);
            return 0;
        }
#endif
        if(address<0x21000 || address>=0x22000) {
            vpi_printf("FAIL firmware_cosim: C address outside UART mapping\n");
            pthread_mutex_unlock(&lock); vpi_control(vpiFinish,1); return 0;
        }
        put(args[0],(uint32_t)(address-0x21000));
        put(args[1],!direction); put(args[2],direction);
        put(args[3],data); put(args[4],direction ? 15u : 0u);
        pending=0; state=1;
    }
    pthread_mutex_unlock(&lock);
    return 0;
}
static void register_tasks(void)
{
    s_vpi_systf_data start={.type=vpiSysTask,.tfname="$firmware_start",.calltf=start_cb};
    s_vpi_systf_data tick={.type=vpiSysTask,.tfname="$firmware_tick",.calltf=tick_cb};
    vpi_register_systf(&start);
    vpi_register_systf(&tick);
}
void (*vlog_startup_routines[])(void)={register_tasks,NULL};
