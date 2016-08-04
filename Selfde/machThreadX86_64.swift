//
//  machX86_64.swift
//  Selfde
//

import Darwin.Mach

#if arch(x86_64) // TODO: i386 support

private extension OpaquePointer {
    init(bitPattern64: UInt64) {
        self.init(bitPattern: UInt(bitPattern64))!
    }

    var bitPattern64: UInt64 {
        return unsafeBitCast(self, to: UInt64.self)
    }
}

private func getStateCount<T>(_ state: T) -> mach_msg_type_number_t {
    return mach_msg_type_number_t(sizeofValue(state) / sizeof(Int32.self))
}

typealias MachMachineThread = MachThreadX86_64

private let hasAVX = CPUHasAVX()

struct MachThreadX86_64 {
    let thread: mach_port_t

    private func getState<T: MachFlavouredState>(_ state: inout T) throws {
        var count = getStateCount(state)
        try handleError(withUnsafeMutablePointer(&state) { pointer in
            let statePtr = thread_state_t(OpaquePointer(pointer))
            return thread_get_state(thread, T.flavour, statePtr, &count)
        })
    }

    private func setState<T: MachFlavouredState>(_ state: inout T) throws {
        let count = getStateCount(state)
        try handleError(withUnsafeMutablePointer(&state) { pointer in
            let statePtr = thread_state_t(OpaquePointer(pointer))
            return thread_set_state(thread, T.flavour, statePtr, count)
        })
    }

    private func getGPRState() throws -> GPRState {
        var state = GPRState()
        try getState(&state)
        return state
    }

    private func setGPRState(_ state: inout GPRState) throws {
        try setState(&state)
    }

    private func getFPUState() throws -> FPUState {
        var state = FPUState()
        try getState(&state)
        return state
    }

    private func setFPUState(_ state: inout FPUState) throws {
        try setState(&state)
    }

    private func getAVXState() throws -> AVXState {
        var state = AVXState()
        try getState(&state)
        return state
    }

    private func setAVXState(_ state: inout AVXState) throws {
        try setState(&state)
    }

    private func getEXCState() throws -> EXCState {
        var state = EXCState()
        try getState(&state)
        return state
    }

    func setHardwareSingleStep(_ enabled: Bool) throws {
        var state = try getGPRState()
        let traceBit: UInt64 = 0x100
        if (enabled) {
            state.__rflags |= traceBit
        } else {
            state.__rflags &= ~traceBit
        }
        try setState(&state)
    }

    func getInstructionPointer() throws -> OpaquePointer {
        return OpaquePointer(bitPattern64: try getGPRState().__rip)
    }

    func setInstructionPointer(_ address: OpaquePointer) throws {
        var state = try getGPRState()
        state.__rip = address.bitPattern64
        try setGPRState(&state)
    }

    func getStackPointer() throws -> OpaquePointer {
        return OpaquePointer(bitPattern64: try getGPRState().__rsp)
    }

    func getRegisterValue(_ id: UInt32, setID: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        switch getRegisterSetKindX86_64(setID) {
        case GPRKindX86_64:
            return try getGPRRegister(id, dest: &dest)
        case FPUKindX86_64:
            return try getFPURegister(id, dest: &dest)
        case EXCKindX86_64:
            return try getEXCRegister(id, dest: &dest)
        default:
            throw ControllerError.invalidRegisterSetID
        }
    }

    func setRegisterValue(_ id: UInt32, setID: UInt32, source: ArraySlice<UInt8>) throws {
        switch getRegisterSetKindX86_64(setID) {
        case GPRKindX86_64:
            return try setGPRRegister(id, source: source)
        case FPUKindX86_64:
            return try setFPURegister(id, source: source)
        case EXCKindX86_64:
            // NB: We can't actually save the EXC state as it is get only.
            fallthrough
        default:
            throw ControllerError.invalidRegisterSetID
        }
    }

    static let registerContextSize: Int = {
        var state = GPRState()
        var fpuState = FPUState()
        var avxState = AVXState()
        var excState = EXCState()
        var dest = [UInt8](repeating: 0, count: 2048)
        var size = dest.count
        dest.withUnsafeMutableBufferPointer { ptr in
            if hasAVX {
                getRegisterContextX86_64(&state, nil, &avxState, &excState, ptr.baseAddress, &size)
            } else {
                getRegisterContextX86_64(&state, &fpuState, nil, &excState, ptr.baseAddress, &size)
            }
        }
        return size
    }()

    func getRegisterContext(_ dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        precondition(dest.count >= MachThreadX86_64.registerContextSize)
        var size = dest.count
        var state = try getGPRState()
        var excState = try getEXCState()
        try dest.withUnsafeMutableBufferPointer { ptr in
            assert(ptr.count == size)
            if hasAVX {
                var avxState = try getAVXState()
                getRegisterContextX86_64(&state, nil, &avxState, &excState, ptr.baseAddress, &size)
            } else {
                var fpuState = try getFPUState()
                getRegisterContextX86_64(&state, &fpuState, nil, &excState, ptr.baseAddress, &size)
            }
        }
        return dest.prefix(size)
    }

    func setRegisterContext(_ source: ArraySlice<UInt8>) throws {
        precondition(source.count == MachThreadX86_64.registerContextSize)
        var state = try getGPRState()
        try source.withUnsafeBufferPointer { ptr in
            if hasAVX {
                var avxState = try getAVXState()
                setRegisterContextX86_64(&state, nil, &avxState, ptr.baseAddress, source.count)
                try setAVXState(&avxState)
            } else {
                var fpuState = try getFPUState()
                setRegisterContextX86_64(&state, &fpuState, nil, ptr.baseAddress, source.count)
                try setFPUState(&fpuState)
            }
        }
        try setGPRState(&state)
        // NB: We can't actually save the EXC state as it is get only.
    }

    private func getGPRRegister(_ id: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        precondition(dest.count >= 8)
        var state = try getGPRState()
        var size = dest.count
        guard dest.withUnsafeMutableBufferPointer({ (ptr: inout UnsafeMutableBufferPointer<UInt8>) -> Bool in
            assert(ptr.count == size)
            return getGPRValueX86_64(id, &state, ptr.baseAddress, &size)
        }) else {
            throw ControllerError.invalidRegisterID
        }
        return dest.prefix(size)
    }

    private func setGPRRegister(_ id: UInt32, source: ArraySlice<UInt8>) throws {
        var state = try getGPRState()
        guard source.withUnsafeBufferPointer({ (ptr: UnsafeBufferPointer<UInt8>) -> Bool in
            assert(ptr.count == source.count)
            return setGPRValueX86_64(id, &state, ptr.baseAddress, source.count)
        }) else {
            throw ControllerError.invalidRegisterID
        }
        try setGPRState(&state)
    }

    private func getFPURegister(_ id: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        precondition(dest.count >= 32)
        var size = dest.count
        if hasAVX {
            var state = try getAVXState()
            guard dest.withUnsafeMutableBufferPointer({ (ptr: inout UnsafeMutableBufferPointer<UInt8>) -> Bool in
                assert(ptr.count == size)
                return getFPUValueX86_64(id, /*fpuState:*/ nil, /*avxState:*/ &state, ptr.baseAddress, &size)
            }) else {
                throw ControllerError.invalidRegisterID
            }
        } else {
            var state = try getFPUState()
            guard dest.withUnsafeMutableBufferPointer({ (ptr: inout UnsafeMutableBufferPointer<UInt8>) -> Bool in
                assert(ptr.count == size)
                return getFPUValueX86_64(id, /*fpuState:*/ &state, /*avxState:*/ nil, ptr.baseAddress, &size)
            }) else {
                throw ControllerError.invalidRegisterID
            }
        }
        return dest.prefix(size)
    }

    private func setFPURegister(_ id: UInt32, source: ArraySlice<UInt8>) throws {
        if hasAVX {
            var state = try getAVXState()
            guard source.withUnsafeBufferPointer({ (ptr: UnsafeBufferPointer<UInt8>) -> Bool in
                assert(ptr.count == source.count)
                return setFPUValueX86_64(id, /*fpuState:*/ nil, /*avxState:*/ &state, ptr.baseAddress, source.count)
            }) else {
                throw ControllerError.invalidRegisterID
            }
            try setAVXState(&state)
        } else {
            var state = try getFPUState()
            guard source.withUnsafeBufferPointer({ (ptr: UnsafeBufferPointer<UInt8>) -> Bool in
                assert(ptr.count == source.count)
                return setFPUValueX86_64(id, /*fpuState:*/ &state, /*avxState:*/ nil, ptr.baseAddress, source.count)
            }) else {
                throw ControllerError.invalidRegisterID
            }
            try setFPUState(&state)
        }
    }

    private func getEXCRegister(_ id: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        precondition(dest.count >= 8)
        var state = try getEXCState()
        var size = dest.count
        guard dest.withUnsafeMutableBufferPointer({ (ptr: inout UnsafeMutableBufferPointer<UInt8>) -> Bool in
            assert(ptr.count == size)
            return getEXCValueX86_64(id, &state, ptr.baseAddress, &size)
        }) else {
            throw ControllerError.invalidRegisterID
        }
        return dest.prefix(size)
    }
}

#endif
