//
//  machController.swift
//  Selfde
//

import Darwin.Mach
import Foundation

/// Implements the Selfde controller for a process running on a Mach kernel.
class MachController: Controller {
    private var state: SelfdeMachControllerState
    private struct BreakpointState {
        let machineState: MachineBreakpointState
        var counter: Int
    }
    private var breakpoints: [COpaquePointer: BreakpointState] = [:]
    private struct AllocationState {
        let address: mach_vm_address_t
        let size: mach_vm_size_t
    }
    private var allocations: [COpaquePointer: AllocationState] = [:]

    init() throws {
        // Create the synchronisation primitives.
        var condition = pthread_cond_t()
        pthread_cond_init(&condition, nil)
        var mutex = pthread_mutex_t()
        pthread_mutex_init(&mutex, nil)

        state = SelfdeMachControllerState(task: 0, controllerThread: 0, msgServerThread: 0, exceptionPort: 0, synchronisationCondition: condition, synchronisationMutex: mutex, caughtException: SelfdeCaughtMachException(thread: 0, exceptionType: 0, exceptionData: nil, exceptionDataSize: 0), hasCaughtException: false)
        try handleError(selfdeInitMachController(&state))

        // Create the exception port and make sure it's connected to the threads we're interested in.
        try handleError(selfdeCreateExceptionPort(state.task, &state.exceptionPort))
        for thread in try getMachThreads() {
            try handleError(selfdeSetExceptionPortForThread(thread, state.exceptionPort))
        }

        // Run the thread that will listen for the exceptions.
        try handleError(selfdeStartExceptionThread(&state))
        print("Initialized controller thread! Controller thread: \(MachThread(state.controllerThread).threadID), message server thread: \(MachThread(state.msgServerThread).threadID)")
    }

    func waitForException() throws -> Exception {
        pthread_mutex_lock(&state.synchronisationMutex)
        while !state.hasCaughtException {
            pthread_cond_wait(&state.synchronisationCondition, &state.synchronisationMutex)
        }
        let result = Exception(thread: MachThread(state.caughtException.thread), type: state.caughtException.exceptionType)
        state.hasCaughtException = false
        free(state.caughtException.exceptionData)
        pthread_mutex_unlock(&state.synchronisationMutex)
        return result
    }

    func getSharedLibraryInfoAddress() throws -> COpaquePointer {
        var dyldInfo = task_dyld_info()
        var count = mach_msg_type_number_t(sizeof(task_dyld_info) / sizeof(Int32))
        let error = withUnsafeMutablePointer(&dyldInfo) {
            task_info(self.state.task, task_flavor_t(TASK_DYLD_INFO), UnsafeMutablePointer<integer_t>($0), &count)
        }
        try handleError(error)
        return COpaquePointer(bitPattern: UInt(dyldInfo.all_image_info_addr))
    }

    func suspendThreads() throws {
        for thread in try getThreads() {
            try thread.suspend()
        }
    }

    func resumeThreads() throws {
        for thread in try getThreads() {
            try thread.resume()
        }
    }

    private func getMachThreads() throws -> [mach_port_t] {
        var threads = thread_act_port_array_t(nil)
        var count = mach_msg_type_number_t(0)
        try handleError(task_threads(state.task, &threads, &count))
        var result = [mach_port_t]()
        for i in 0..<count {
            let thread = threads[Int(i)]
            if thread == state.controllerThread || thread == state.msgServerThread {
                continue;
            }
            result.append(thread)
        }
        return result
    }

    func getThreads() throws -> [Thread] {
        var threads = thread_act_port_array_t(nil)
        var count = mach_msg_type_number_t(0)
        try handleError(task_threads(state.task, &threads, &count))
        var result = [Thread]()
        for i in 0..<count {
            let thread = threads[Int(i)]
            if thread == state.controllerThread || thread == state.msgServerThread {
                continue;
            }
            result.append(MachThread(thread))
        }
        return result
    }

    /// Gives the given memory ALL protections.
    private func memoryProtectAll(address: COpaquePointer, size: vm_size_t) throws {
        let addr = vm_address_t(unsafeBitCast(address, UInt.self))
        try handleError(vm_protect(state.task, addr, size, boolean_t(0), getVMProtAll()))
    }

    func installBreakpoint(address: COpaquePointer) throws -> Breakpoint {
        if let index = breakpoints.indexForKey(address) {
            var bp = breakpoints[index].1
            bp.counter += 1
            breakpoints.updateValue(bp, forKey: address)
            return Breakpoint(address: address)
        }
        // Make sure we can write to the address.
        try memoryProtectAll(address, size: MachineBreakpointState.numberOfBytesToPatch)
        let machineState = MachineBreakpointState.create(address)
        breakpoints[address] = BreakpointState(machineState: machineState, counter: 1)
        return Breakpoint(address: address)
    }

    private func restoreBreakpointsOriginalInstruction(breakpoint: (address: COpaquePointer, BreakpointState)) {
        breakpoint.1.machineState.restoreOriginalInstruction(breakpoint.address)
    }

    func removeBreakpoint(breakpoint: Breakpoint) throws {
        guard let index = breakpoints.indexForKey(breakpoint.address) else {
            throw ControllerError.InvalidBreakpoint
        }
        let keyValue = breakpoints[index]
        var bp = keyValue.1
        bp.counter -= 1
        guard bp.counter < 1 else {
            breakpoints.updateValue(bp, forKey: breakpoint.address)
            return
        }
        restoreBreakpointsOriginalInstruction(keyValue)
        breakpoints.removeAtIndex(index)
    }

    func allocate(size: Int, permissions: MemoryPermissions) throws -> COpaquePointer {
        var address = mach_vm_address_t()
        let allocationSize = mach_vm_size_t(size)
        try handleError(mach_vm_allocate(state.task, &address, allocationSize, 1))
        var protection: vm_prot_t = 0
        if permissions.contains(.Read) {
            protection |= getVMProtRead()
        }
        if permissions.contains(.Write) {
            protection |= getVMProtWrite()
        }
        if permissions.contains(.Execute) {
            protection |= getVMProtExecute()
        }
        do {
            try handleError(mach_vm_protect(state.task, address, allocationSize, 0, protection))
        } catch {
            mach_vm_deallocate(state.task, address, allocationSize)
            throw error
        }
        let result = COpaquePointer(bitPattern: UInt(address))
        allocations[result] = AllocationState(address: address, size: allocationSize)
        return result
    }

    func deallocate(address: COpaquePointer) throws {
        guard let allocation = allocations[address] else {
            throw ControllerError.InvalidAllocation
        }
        try handleError(mach_vm_deallocate(state.task, allocation.address, allocation.size))
    }
}
