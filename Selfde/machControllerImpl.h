//
//  machControllerImpl.h
//  Selfde
//

#ifndef machControllerImpl_h
#define machControllerImpl_h

#include <mach/mach.h>
#include <pthread.h>
#include <dispatch/dispatch.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SelfdeMachException {
    mach_port_t thread;
    exception_type_t exception;
} SelfdeMachException;

typedef struct SelfdeMachControllerState {
    mach_port_t task;
    mach_port_t controllerThread;
    mach_port_t msgServerThread;
    mach_port_t exceptionPort;
} SelfdeMachControllerState;

int selfdeInitMachController(SelfdeMachControllerState *state);
int selfdeWaitForException(SelfdeMachControllerState *state, SelfdeMachException *exception);

vm_prot_t getVMProtAll();
vm_prot_t getVMProtRead();
vm_prot_t getVMProtWrite();
vm_prot_t getVMProtExecute();

#ifdef __cplusplus
}
#endif

#endif /* machControllerImpl_h */
