//
//  machException.swift
//  Selfde
//

import Darwin.Mach

// An exception that occured, like a breakpoint.
public struct Exception {
    public let thread: Thread
    public let type: exception_type_t
    // Mach kernel exception data.
    public let data: [UInt]

    public init(thread: Thread, type: exception_type_t, data: [UInt]) {
        self.thread = thread
        self.type = type
        self.data = data
    }
}

public extension Exception {
    public var isBreakpoint: Bool {
        return type == EXC_BREAKPOINT
    }

    public var isBadAccess: Bool {
        return type == EXC_BAD_ACCESS
    }

    public var isBadInstruction: Bool {
        return type == EXC_BAD_INSTRUCTION
    }

    // The signal number of this exception that's compatible with the remote debugging protocol.
    public var signalNumber: Int32 {
        switch type {
        case EXC_BREAKPOINT:
            return SIGTRAP
        // LLDB:
        /* We translate the /usr/include/mach/exception_types.h exception types
        (e.g. EXC_BAD_ACCESS) to the fake BSD signal numbers that gdb uses
        in include/gdb/signals.h (e.g. TARGET_EXC_BAD_ACCESS).  These hard
        coded values for TARGET_EXC_BAD_ACCESS et al must match the gdb
        values in its include/gdb/signals.h.  */
        case EXC_BAD_ACCESS:
            return 0x91 //TARGET_EXC_BAD_ACCESS
        case EXC_BAD_INSTRUCTION:
            return 0x92 //TARGET_EXC_BAD_INSTRUCTION
        case EXC_ARITHMETIC:
            return 0x93 //TARGET_EXC_ARITHMETIC
        case EXC_EMULATION:
            return 0x94 //TARGET_EXC_EMULATION
        case EXC_SOFTWARE:
            if (data.count == 2 && data[0] == UInt(EXC_SOFT_SIGNAL)) {
                return Int32(data[1])
            }
            return 0x95 //TARGET_EXC_SOFTWARE
        default:
            return 0
        }
    }

    public var reason: String {
        switch type {
        case EXC_BAD_ACCESS:
            return "bad access"
        case EXC_BAD_INSTRUCTION:
            return "bad instruction"
        case EXC_ARITHMETIC:
            return "arithmetic"
        case EXC_EMULATION:
            return "emulation"
        case EXC_SOFTWARE:
            return "software"
        case EXC_BREAKPOINT:
            return "breakpoint"
        case EXC_SYSCALL:
            return "syscall"
        case EXC_MACH_SYSCALL:
            return "mach syscall"
        case EXC_RPC_ALERT:
            return "RPC alert"
        case EXC_GUARD:
            return "guard"
        case EXC_CRASH:
            return "crash"
        case EXC_RESOURCE:
            return "resource"
        case EXC_GUARD:
            return "guard"
        case EXC_CORPSE_NOTIFY:
            return "corpse notify"
        default:
            return "<unknown>"
        }
    }

    // Creates an exception that describes the initial stop reason of the thread for the remote debugger after the
    // debugger attached to the process.
    public static func stopOnDebuggerAttachmentExceptionForThread(thread: Thread) -> Exception {
        return Exception(thread: thread, type: exception_type_t(EXC_SOFTWARE), data: [UInt(EXC_SOFT_SIGNAL), 0x11])
    }
}
