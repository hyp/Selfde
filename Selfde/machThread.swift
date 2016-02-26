//
//  machThread.swift
//  Selfde
//

import Darwin.Mach

public func getCurrentThread() throws -> Thread {
    return MachThread(mach_thread_self())
}

public func ==(lhs: Thread, rhs: Thread) -> Bool {
    return lhs.opaqueValue == rhs.opaqueValue
}

public func !=(lhs: Thread, rhs: Thread) -> Bool {
    return lhs.opaqueValue != rhs.opaqueValue
}

struct MachThread: Thread {
    private var impl: MachMachineThread
    private var thread: mach_port_t {
        return impl.thread
    }

    init (_ value: mach_port_t) {
        impl = MachMachineThread(thread: value)
    }

    func getInstructionPointer() throws -> COpaquePointer {
        return try impl.getInstructionPointer()
    }

    func setInstructionPointer(address: COpaquePointer) throws {
        try impl.setInstructionPointer(address)
    }

    func getStackPointer() throws -> COpaquePointer {
        return try impl.getStackPointer()
    }

    func beginSingleStepMode() throws {
        try impl.setHardwareSingleStep(true)
    }

    func endSingleStepMode() throws {
        try impl.setHardwareSingleStep(false)
    }

    func suspend() throws {
        try handleError(thread_suspend(thread))
    }

    func resume() throws {
        try handleError(thread_resume(thread))
    }

    func abort() throws {
        try handleError(thread_abort(thread))
    }

    private func getBasicInfo() throws -> thread_basic_info {
        var infoData: thread_info_data_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) // ?
        var size = mach_msg_type_number_t(THREAD_INFO_MAX)
        try handleError(withUnsafeMutablePointer(&infoData) { pointer in
            let statePtr = thread_info_t(COpaquePointer(pointer))
            return thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), statePtr, &size);
            })
        return withUnsafePointer(&infoData) { pointer -> thread_basic_info in
            let basicInfoPtr = thread_basic_info_t(COpaquePointer(pointer))
            return basicInfoPtr.memory
        }
    }

    func getRunState() throws -> RunState {
        switch try getBasicInfo().run_state {
        case TH_STATE_RUNNING:
            return .Running
        case TH_STATE_STOPPED:
            return .Stopped
        case TH_STATE_WAITING:
            return .Waiting
        case TH_STATE_UNINTERRUPTIBLE:
            return .Uninterruptible
        case TH_STATE_HALTED:
            return .Halted
        default:
            throw ControllerError.InvalidRunState
        }
    }

    var opaqueValue: Int {
        return Int(thread)
    }
}
