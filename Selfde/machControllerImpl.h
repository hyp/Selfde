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

typedef struct SelfdeCaughtMachException {
    mach_port_t thread;
    exception_type_t exceptionType;
    mach_exception_data_type_t *exceptionData;
    mach_msg_type_number_t exceptionDataSize;
} SelfdeCaughtMachException;

typedef struct SelfdeMachControllerState {
    mach_port_t task;
    mach_port_t controllerThread;
    mach_port_t msgServerThread;
    mach_port_t exceptionPort;
    pthread_cond_t synchronisationCondition;
    pthread_mutex_t synchronisationMutex;
    SelfdeCaughtMachException caughtException;
    bool hasCaughtException;
} SelfdeMachControllerState;

kern_return_t selfdeCreateExceptionPort(mach_port_t task, mach_port_t *exceptionPort);
kern_return_t selfdeSetExceptionPortForThread(mach_port_t thread, mach_port_t exceptionPort);
kern_return_t selfdeStartExceptionThread(SelfdeMachControllerState *state);
int selfdeInitMachController(SelfdeMachControllerState *state);

vm_prot_t getVMProtAll();
vm_prot_t getVMProtRead();
vm_prot_t getVMProtWrite();
vm_prot_t getVMProtExecute();

void selfdeJumpToAddress(const void *address);

#ifdef __cplusplus
}
#endif

#endif /* machControllerImpl_h */
