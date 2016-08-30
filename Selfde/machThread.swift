//
//  machThread.swift
//  Selfde
//

import Darwin.Mach

public func getCurrentThread() throws -> Thread {
    return Thread(mach_thread_self())
}

public func ==(lhs: Thread, rhs: Thread) -> Bool {
    return lhs.threadID == rhs.threadID
}

public func !=(lhs: Thread, rhs: Thread) -> Bool {
    return lhs.threadID != rhs.threadID
}

public func getRegisterContextSize() -> Int {
    return MachMachineThread.registerContextSize
}

public struct Thread {
    private var impl: MachMachineThread
    var thread: mach_port_t {
        return impl.thread
    }

    init (_ value: mach_port_t) {
        impl = MachMachineThread(thread: value)
    }

    public func getInstructionPointer() throws -> Address {
        return try impl.getInstructionPointer()
    }

    public func setInstructionPointer(_ address: Address) throws {
        try impl.setInstructionPointer(address)
    }

    public func getStackPointer() throws -> Address {
        return try impl.getStackPointer()
    }

    public func getRegisterValue(_ id: UInt32, setID: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        return try impl.getRegisterValue(id, setID: setID, dest: &dest)
    }

    public func setRegisterValue(_ id: UInt32, setID: UInt32, source: ArraySlice<UInt8>) throws {
        return try impl.setRegisterValue(id, setID: setID, source: source)
    }

    public func getRegisterContext(_ dest: inout [UInt8]) throws -> ArraySlice<UInt8> {
        return try impl.getRegisterContext(&dest)
    }

    public func setRegisterContext(_ source: ArraySlice<UInt8>) throws {
        return try impl.setRegisterContext(source)
    }

    public func beginSingleStepMode() throws {
        try impl.setHardwareSingleStep(true)
    }

    public func endSingleStepMode() throws {
        try impl.setHardwareSingleStep(false)
    }

    public func suspend() throws {
        try handleError(thread_suspend(thread))
    }

    public func resume() throws {
        try handleError(thread_resume(thread))
    }

    public func syncState() throws {
        try handleError(thread_abort_safely(thread))
    }

    private func getBasicInfo() throws -> thread_basic_info {
        var infoData: thread_info_data_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) // ?
        var size = mach_msg_type_number_t(THREAD_INFO_MAX)
        try handleError(withUnsafeMutablePointer(to: &infoData) { pointer in
            let statePtr = thread_info_t(OpaquePointer(pointer))
            return thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), statePtr, &size)
        })
        return withUnsafePointer(to: &infoData) { pointer -> thread_basic_info in
            let basicInfoPtr = thread_basic_info_t(OpaquePointer(pointer))
            return basicInfoPtr.pointee
        }
    }

    private func getIdentifierInfo() throws -> thread_identifier_info {
        var info = thread_identifier_info()
        var size = mach_msg_type_number_t(MemoryLayout<thread_identifier_info>.size / MemoryLayout<integer_t>.size)
        try handleError(withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { pointer in
                thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), pointer, &size)
            }
        })
        return info
    }

    public func getRunState() throws -> RunState {
        switch try getBasicInfo().run_state {
        case TH_STATE_RUNNING:
            return .running
        case TH_STATE_STOPPED:
            return .stopped
        case TH_STATE_WAITING:
            return .waiting
        case TH_STATE_UNINTERRUPTIBLE:
            return .uninterruptible
        case TH_STATE_HALTED:
            return .halted
        default:
            throw ControllerError.invalidRunState
        }
    }

    public func getSuspendCount() throws -> Int {
        return Int(try getBasicInfo().suspend_count)
    }

    public var threadID: ThreadID {
        do {
            return try getIdentifierInfo().thread_id
        } catch {
            return ThreadID(thread)
        }
    }

    public func getDispatchQueueAddress() throws -> Address {
        return Address(bitPattern: UInt(try getIdentifierInfo().dispatch_qaddr))
    }
}
