//
//  machException.swift
//  Selfde
//

import Darwin.Mach

// An exception that occured, like a breakpoint.
public struct Exception {
    public let thread: Thread
    public let type: exception_type_t
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
}
