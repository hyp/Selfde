//
//  machRegisterSetsX86_64.swift
//  Selfde
//

import Darwin.Mach

struct RegisterSetKind: OptionSetType {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    
    static let GPR = RegisterSetKind(rawValue: 1)
    static let FPU = RegisterSetKind(rawValue: 2)
    static let EXC = RegisterSetKind(rawValue: 4)
    static let DBG = RegisterSetKind(rawValue: 8)
    static let All: RegisterSetKind = [GPR, FPU, EXC, DBG]
}

// Protocol that's used to determine the flavour of a state.
protocol MachFlavouredState {
    static var flavour: thread_state_flavor_t { get }
}

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

extension x86_debug_state64_t: MachFlavouredState {
    static var flavour: thread_state_flavor_t {
        return x86_DEBUG_STATE64
    }
}

// General purpose registers.
typealias GPRState = x86_thread_state64_t
typealias FPUState = x86_float_state64_t
typealias AVXState = x86_avx_state64_t
typealias EXCState = x86_exception_state64_t
typealias DBGState = x86_debug_state64_t

struct RegisterState {
    var GPR: GPRState
    var FPU: FPUState
    var AVX: AVXState
    var EXC: EXCState
    var DBG: DBGState
}
