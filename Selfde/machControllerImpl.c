//
//  machControllerImpl.c
//  Selfde
//

#include "machControllerImpl.h"
#include <sys/types.h>
#include <sys/ptrace.h>
#include <pthread.h>
#include <stdlib.h>
#include <assert.h>

// Global state only accessed by the exception handler thread.
static SelfdeCaughtMachException caughtExceptionState;
static bool isExceptionCaught;

kern_return_t catch_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exceptionType, mach_exception_data_t exceptionData, mach_msg_type_number_t exceptionDataSize) {
    // Suspend the thread with the exception.
    thread_suspend(thread);
    thread_abort_safely(thread);

    // Save the exception information.
    caughtExceptionState.thread = thread;
    caughtExceptionState.exceptionType = exceptionType;
    caughtExceptionState.exceptionData = malloc(sizeof(mach_exception_data_type_t) * exceptionDataSize);
    for (mach_msg_type_number_t i = 0; i < exceptionDataSize; ++i) {
        caughtExceptionState.exceptionData[i] = exceptionData[i];
    }
    caughtExceptionState.exceptionDataSize = exceptionDataSize;
    isExceptionCaught = true;

    return KERN_SUCCESS;
}

// Autogenerated somewhere in the system Libs..
extern boolean_t exc_server(mach_msg_header_t *msg, mach_msg_header_t *reply);

static const SelfdeCaughtMachException *selfdeWaitForException(mach_port_t exceptionPort) {
    isExceptionCaught = false;
    mach_msg_server_once(exc_server, 2048, exceptionPort, 0);
    if (!isExceptionCaught) {
        return NULL;
    }
    return &caughtExceptionState;
}

// Context that's passed into the exception handler thread.
// It is valid until the semaphore is signalled.
typedef struct ExceptionHandlerContext {
    dispatch_semaphore_t semaphore;
    SelfdeMachControllerState *state;
} ExceptionHandlerContext;

static void *exceptionHandlerThreadMain(void *arg) {
#if defined (__APPLE__)
    pthread_setname_np("Exception monitoring thread");
#endif
    // Get the port and set the message server thread in the state.
    ExceptionHandlerContext *context = (ExceptionHandlerContext *)arg;
    mach_port_t port = context->state->exceptionPort;
    context->state->msgServerThread = mach_thread_self();
    SelfdeMachControllerState *state = context->state;

    // Resume the controller thread and invalidate the context..
    dispatch_semaphore_signal(context->semaphore);
    context = NULL;

    // Run the server.
    while (true) {
        const SelfdeCaughtMachException *exception = selfdeWaitForException(port);
        if (exception == NULL) {
            continue;
        }
        // Dispatch the message.
        pthread_mutex_lock(&state->synchronisationMutex);
        state->caughtException = *exception;
        state->hasCaughtException = true;
        pthread_cond_signal(&state->synchronisationCondition);
        pthread_mutex_unlock(&state->synchronisationMutex);
    }
}

kern_return_t selfdeCreateExceptionPort(mach_port_t task, mach_port_t *exceptionPort) {
    mach_error_t ret = mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, exceptionPort);
    if (ret != KERN_SUCCESS) {
        return ret;
    }
    ret = mach_port_insert_right(task, *exceptionPort, *exceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    if (ret != KERN_SUCCESS) {
        return ret;
    }
    return KERN_SUCCESS;
}

kern_return_t selfdeSetExceptionPortForThread(mach_port_t thread, mach_port_t exceptionPort) {
    return thread_set_exception_ports(thread, (EXC_MASK_BAD_ACCESS |
                                               EXC_MASK_BAD_INSTRUCTION |
                                               EXC_MASK_ARITHMETIC |
                                               EXC_MASK_EMULATION |
                                               EXC_MASK_SOFTWARE |
                                               EXC_MASK_BREAKPOINT |
                                               EXC_MASK_RPC_ALERT |
                                               EXC_MASK_MACHINE), exceptionPort, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
}

kern_return_t selfdeStartExceptionThread(SelfdeMachControllerState *state) {
    pthread_t exceptionHadlerThread;
    ExceptionHandlerContext *context = malloc(sizeof(ExceptionHandlerContext));
    context->semaphore = dispatch_semaphore_create(0);
    context->state = state;
    int ret = pthread_create(&exceptionHadlerThread, NULL, exceptionHandlerThreadMain, context);
    if (ret != 0) {
        return ret;
    }
    dispatch_semaphore_wait(context->semaphore, DISPATCH_TIME_FOREVER);
    dispatch_release(context->semaphore);
    free(context);
    return KERN_SUCCESS;
}

int selfdeInitMachController(SelfdeMachControllerState *state) {
    // TODO: check
    state->task = mach_task_self();
    state->controllerThread = mach_thread_self();
    state->msgServerThread = state->controllerThread;
    return KERN_SUCCESS;
}

vm_prot_t getVMProtAll() {
    return VM_PROT_ALL;
}

vm_prot_t getVMProtRead() {
    return VM_PROT_READ;
}

vm_prot_t getVMProtWrite() {
    return VM_PROT_WRITE;
}

vm_prot_t getVMProtExecute() {
    return VM_PROT_EXECUTE;
}

void selfdeJumpToAddress(const void *address) {
    void (*fn)() = address;
    fn();
}
