//
//  machRegisterSetsX86_64.swift
//  Selfde
//

import Darwin.Mach

// Protocol that's used to determine the flavour of a state.
protocol MachFlavouredState {
    static var flavour: thread_state_flavor_t { get }
}

#if arch(x86_64)

extension x86_thread_state64_t: MachFlavouredState {
    static var flavour: thread_state_flavor_t {
        return x86_THREAD_STATE64
    }
}

extension x86_float_state64_t: MachFlavouredState {
    static var flavour: thread_state_flavor_t {
        return x86_FLOAT_STATE64
    }
}

extension x86_avx_state64_t: MachFlavouredState {
    static var flavour: thread_state_flavor_t {
        return x86_AVX_STATE64
    }
}

extension x86_exception_state64_t: MachFlavouredState {
    static var flavour: thread_state_flavor_t {
        return x86_EXCEPTION_STATE64
    }
}

typealias GPRState = x86_thread_state64_t
typealias FPUState = x86_float_state64_t
typealias AVXState = x86_avx_state64_t
typealias EXCState = x86_exception_state64_t

#endif
