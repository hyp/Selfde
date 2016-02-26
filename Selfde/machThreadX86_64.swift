//
//  machX86_64.swift
//  Selfde
//

import Darwin.Mach

private extension COpaquePointer {
    init(bitPattern64: UInt64) {
        self.init(bitPattern: UInt(bitPattern64))
    }
    
    var bitPattern64: UInt64 {
        return unsafeBitCast(self, UInt64.self)
    }
}

private func getStateCount<T>(state: T) -> mach_msg_type_number_t {
    return mach_msg_type_number_t(sizeofValue(state) / sizeof(Int32))
}

typealias MachMachineThread = MachThreadX86_64

// TODO: other register sets.
struct MachThreadX86_64 {
    let thread: mach_port_t
    static var hasAVX: Bool = isAVXPresent()

    private func getState<T: MachFlavouredState>(inout state: T) throws {
        var count = getStateCount(state)
        try handleError(withUnsafeMutablePointer(&state) { pointer in
            let statePtr = thread_state_t(COpaquePointer(pointer))
            return thread_get_state(thread, T.flavour, statePtr, &count)
        })
    }

    private func setState<T: MachFlavouredState>(inout state: T) throws {
        let count = getStateCount(state)
        try handleError(withUnsafeMutablePointer(&state) { pointer in
            let statePtr = thread_state_t(COpaquePointer(pointer))
            return thread_set_state(thread, T.flavour, statePtr, count)
        })
    }

    private func getGPRState() throws -> GPRState {
        var state = GPRState()
        try getState(&state)
        return state
    }

    private func setGPRState(inout state: GPRState) throws {
        try setState(&state)
    }

    func setHardwareSingleStep(enabled: Bool) throws {
        var state = try getGPRState()
        let traceBit: UInt64 = 0x100
        if (enabled) {
            state.__rflags |= traceBit
        } else {
            state.__rflags &= ~traceBit
        }
        try setState(&state)
    }

    func forEachGPR(mutate: Bool = false, handler: (String, COpaquePointer) -> COpaquePointer) throws {
        func reg(name: String, inout _ value: UInt64) {
            value = handler(name, COpaquePointer(bitPattern64: value)).bitPattern64
        }
        var state = try getGPRState()
        reg("rax", &state.__rax)
        reg("rbx", &state.__rbx)
        reg("rcx", &state.__rcx)
        reg("rdx", &state.__rdx)
        reg("rdi", &state.__rdi)
        reg("rsi", &state.__rsi)
        reg("rbp", &state.__rbp)
        reg("rsp", &state.__rsp)
        reg("r8", &state.__r8)
        reg("r9", &state.__r9)
        reg("r10", &state.__r10)
        reg("r11", &state.__r11)
        reg("r12", &state.__r12)
        reg("r13", &state.__r13)
        reg("r14", &state.__r14)
        reg("r15", &state.__r15)
        reg("rip", &state.__rip)
        reg("rflags", &state.__rflags)
        reg("cs", &state.__cs)
        reg("fs", &state.__fs)
        reg("gs", &state.__gs)
        if mutate {
            try setGPRState(&state)
        }
    }

    func getInstructionPointer() throws -> COpaquePointer {
        return COpaquePointer(bitPattern64: try getGPRState().__rip)
    }

    func setInstructionPointer(address: COpaquePointer) throws {
        var state = try getGPRState()
        state.__rip = address.bitPattern64
        try setGPRState(&state)
    }

    func getStackPointer() throws -> COpaquePointer {
        return COpaquePointer(bitPattern64: try getGPRState().__rsp)
    }
}
