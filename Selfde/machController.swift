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
    private struct AllocationState {
        let address: mach_vm_address_t
        let size: mach_vm_size_t
    }
    private var allocations: [COpaquePointer: AllocationState] = [:]

    init() throws {
        state = SelfdeMachControllerState(task: 0, controllerThread: 0, msgServerThread: 0, exceptionPort: 0)
        // Init
        // Init exception handler.
        // TODO: handle errors.
        try handleError(selfdeInitMachController(&state))
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
