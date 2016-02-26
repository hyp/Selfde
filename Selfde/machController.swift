//
//  machController.swift
//  Selfde
//

import Darwin.Mach

/// Implements the Selfde controller for a process running on a Mach kernel.
class MachController: Controller {
    private var state: SelfdeMachControllerState
    private struct BreakpointState {
        let machineState: MachineBreakpointState
    }
    private var breakpoints: [COpaquePointer: BreakpointState] = [:]

    init() throws {
        state = SelfdeMachControllerState(task: 0, controllerThread: 0, msgServerThread: 0, exceptionPort: 0)
        // Init
        // Init exception handler.
        // TODO: handle errors.
        try handleError(selfdeInitMachController(&state))
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
        guard breakpoints[address] == nil else {
            throw ControllerError.BreakpointAlreadyInstalled
        }
        // Make sure we can write to the address.
        try memoryProtectAll(address, size: MachineBreakpointState.numberOfBytesToPatch)
        let (machineState, expectedHitAddress) = MachineBreakpointState.create(address)
        breakpoints[address] = BreakpointState(machineState: machineState)
        return Breakpoint(address: address, expectedHitAddress: expectedHitAddress)
    }

    private func restoreBreakpointsOriginalInstruction(breakpoint: (address: COpaquePointer, BreakpointState)) {
        breakpoint.1.machineState.restoreOriginalInstruction(breakpoint.address)
    }

    func removeBreakpoint(breakpoint: Breakpoint) throws {
        guard let index = breakpoints.indexForKey(breakpoint.address) else {
            throw ControllerError.InvalidBreakpoint
        }
        restoreBreakpointsOriginalInstruction(breakpoints[index])
        breakpoints.removeAtIndex(index)
    }

    func waitForException() throws -> Exception {
        var exception = SelfdeMachException()
        try handleError(selfdeWaitForException(&state, &exception))
        return Exception(thread: MachThread(exception.thread), code: exception.exception)
    }
}
