//
//  machController.swift
//  Selfde
//

import Darwin.Mach
import Foundation

public struct ControllerInterrupter {
    private unowned let controller: Controller

    public func sendInterrupt(_ function: @noescape () -> ()) {
        controller.interrupt(function)
    }
}

/// Implements the Selfde controller for a process running on a Mach kernel.
public class Controller {
    private let conditionLock: Condition
    private var state: SelfdeMachControllerState
    private var hasInterrupt: Bool = false
    private var utilityThreadPort: mach_port_t // Can be used for things like listening for remote debugging commands.
    private var utilityThread: Foundation.Thread?
    private struct BreakpointState {
        let machineState: MachineBreakpointState
        let landingAddress: Address
        var counter: Int
    }
    private var breakpoints: [Address: BreakpointState] = [:]
    private var breakpointLandingAddresses: [Address: Address] = [:]
    private struct AllocationState {
        let address: mach_vm_address_t
        let size: mach_vm_size_t
    }
    private var allocations: [Address: AllocationState] = [:]

    init() throws {
        // Create the synchronisation primitives.
        conditionLock = try Condition()
        let thread = mach_thread_self()
        state = SelfdeMachControllerState(task: getMachTaskSelf(), controllerThread: thread, msgServerThread: thread, exceptionPort: 0, synchronisationCondition: conditionLock.cond, synchronisationMutex: conditionLock.mutex, caughtException: SelfdeCaughtMachException(thread: 0, exceptionType: 0, exceptionData: nil, exceptionDataSize: 0), hasCaughtException: false)
        utilityThreadPort = thread
    }

    deinit {
        if state.msgServerThread != state.controllerThread {
            if thread_terminate(state.msgServerThread) != KERN_SUCCESS {
                return
            }
        }
        if let thread = utilityThread, !thread.isFinished {
            if thread_terminate(utilityThreadPort) != KERN_SUCCESS {
                return
            }
            utilityThread = nil
        }
        // conditionLock won't be deallocated before the end of deinit therefore its OK
        // to just kill the threads that use it and then deallocate it as those threads
        // won't be able to refer to it anymore.
    }

    /// Starts a thread that listens for exceptions like breakpoints for
    /// the given threads.
    public func initializeExceptionHandlingForThreads(_ threads: [Thread]) throws {
        // Create the exception port and make sure it's connected to the threads we're interested in.
        try handleError(selfdeCreateExceptionPort(state.task, &state.exceptionPort))
        for thread in threads {
            try handleError(selfdeSetExceptionPortForThread(thread.thread, state.exceptionPort))
        }

        // Run the thread that will listen for the exceptions.
        try handleError(selfdeStartExceptionThread(&state))
    }

    private func interrupt(_ function: @noescape () -> ()) {
        conditionLock.lock()
        hasInterrupt = true
        function()
        conditionLock.signal()
        conditionLock.unlock()
    }

    public func runUtilityThread(_ function: (ControllerInterrupter) -> ()) {
        final class UtilityThread: Foundation.Thread {
            unowned let controller: Controller
            let function: (ControllerInterrupter) -> ()

            init(controller: Controller, function: (ControllerInterrupter) -> ()) {
                self.controller = controller
                self.function = function
                super.init()
            }

            override func main() {
                controller.interrupt {
                    controller.utilityThreadPort = mach_thread_self()
                }
                function(ControllerInterrupter(controller: controller))
            }
        }
        let thread = UtilityThread(controller: self, function: function)
        utilityThread = thread
        assert(hasInterrupt == false)
        thread.start()

        // Wait for the utility thread to interrupt us so that we know its mach port.
        conditionLock.lock()
        while !hasInterrupt {
            conditionLock.wait()
        }
        hasInterrupt = false
        conditionLock.unlock()
    }

    public func waitForEvent(interruptHandler: (() -> ())? = nil) throws -> ControllerEvent {
        conditionLock.lock()
        while !state.hasCaughtException && !hasInterrupt {
            conditionLock.wait()
        }
        guard state.hasCaughtException else {
            assert(hasInterrupt)
            interruptHandler?()
            hasInterrupt = false
            conditionLock.unlock()
            return .interrupted
        }
        let data = UnsafeMutableBufferPointer<mach_exception_data_type_t>(start: state.caughtException.exceptionData, count: Int(state.caughtException.exceptionDataSize))
        let result = Exception(thread: Thread(state.caughtException.thread), type: state.caughtException.exceptionType, data: Array(data.map { UInt($0) }))
        state.hasCaughtException = false
        hasInterrupt = false
        free(state.caughtException.exceptionData)
        conditionLock.unlock()
        try handleException(result)
        return .caughtException(result)
    }

    private func handleException(_ exception: Exception) throws {
        guard exception.isBreakpoint else {
            return
        }
        // We want to move the IP back to the breakpoint's address when we hit a breakpoint.
        let IP = try exception.thread.getInstructionPointer()
        guard let address = breakpointLandingAddresses[IP] else {
            // We could have simply stepped.
            return
        }
        try exception.thread.setInstructionPointer(address)
    }

    public func getSharedLibraryInfoAddress() throws -> Address {
        var dyldInfo = task_dyld_info()
        var count = mach_msg_type_number_t(sizeof(task_dyld_info.self) / sizeof(Int32.self))
        let error = withUnsafeMutablePointer(&dyldInfo) {
            task_info(self.state.task, task_flavor_t(TASK_DYLD_INFO), UnsafeMutablePointer<integer_t>($0), &count)
        }
        try handleError(error)
        return Address(bitPattern: UInt(dyldInfo.all_image_info_addr))
    }

    public func suspendThreads() throws {
        for thread in try getThreads() {
            try thread.suspend()
        }
    }

    public func resumeThreads() throws {
        for thread in try getThreads() {
            try thread.resume()
        }
    }

    public func getThreads() throws -> [Thread] {
        var threads = thread_act_port_array_t(nil)
        var count = mach_msg_type_number_t(0)
        try handleError(task_threads(state.task, &threads, &count))
        var result = [Thread]()
        for i in 0..<count {
            let thread = threads?[Int(i)]
            if thread == state.controllerThread || thread == state.msgServerThread || thread == utilityThreadPort {
                continue;
            }
            result.append(Thread(thread!))
        }
        return result
    }

    /// Gives the given memory ALL protections.
    private func memoryProtectAll(_ address: Address, size: vm_size_t) throws {
        let addr = vm_address_t(address.bitPattern)
        try handleError(vm_protect(state.task, addr, size, boolean_t(0), getVMProtAll()))
    }

    public func installBreakpoint(at address: Address) throws -> Breakpoint {
        if let index = breakpoints.index(forKey: address) {
            var bp = breakpoints[index].1
            bp.counter += 1
            breakpoints.updateValue(bp, forKey: address)
            return Breakpoint(address: address)
        }
        // Make sure we can write to the address.
        try memoryProtectAll(address, size: MachineBreakpointState.numberOfBytesToPatch)
        let (machineState, landingAddress) = MachineBreakpointState.create(at: address)
        breakpoints[address] = BreakpointState(machineState: machineState, landingAddress: landingAddress, counter: 1)
        breakpointLandingAddresses[landingAddress] = address
        return Breakpoint(address: address)
    }

	private func restoreBreakpointsOriginalInstruction(at address: Address, state: BreakpointState) {
		state.machineState.restoreOriginalInstruction(at: address)
    }

    public func removeBreakpoint(_ breakpoint: Breakpoint) throws {
        guard let index = breakpoints.index(forKey: breakpoint.address) else {
            throw ControllerError.invalidBreakpoint
        }
        let keyValue = breakpoints[index]
        var bp = keyValue.1
        bp.counter -= 1
        guard bp.counter < 1 else {
            breakpoints.updateValue(bp, forKey: breakpoint.address)
            return
        }
		restoreBreakpointsOriginalInstruction(at: keyValue.key, state: keyValue.value)
        breakpoints.remove(at: index)
        guard let address = breakpointLandingAddresses.removeValue(forKey: bp.landingAddress) else {
            assertionFailure()
            return
        }
        assert(address == breakpoint.address)
    }

    public func allocate(_ size: Int, permissions: MemoryPermissions) throws -> Address {
        var address = mach_vm_address_t()
        let allocationSize = mach_vm_size_t(size)
        try handleError(mach_vm_allocate(state.task, &address, allocationSize, 1))
        var protection: vm_prot_t = 0
        if permissions.contains(.read) {
            protection |= getVMProtRead()
        }
        if permissions.contains(.write) {
            protection |= getVMProtWrite()
        }
        if permissions.contains(.execute) {
            protection |= getVMProtExecute()
        }
        do {
            try handleError(mach_vm_protect(state.task, address, allocationSize, 0, protection))
        } catch {
            mach_vm_deallocate(state.task, address, allocationSize)
            throw error
        }
        let result = Address(bitPattern: UInt(address))
        allocations[result] = AllocationState(address: address, size: allocationSize)
        return result
    }

    public func deallocate(_ address: Address) throws {
        guard let allocation = allocations[address] else {
            throw ControllerError.invalidAllocation
        }
        try handleError(mach_vm_deallocate(state.task, allocation.address, allocation.size))
    }
}
