//
//  breakpointX86_64.swift
//  Selfde
//

#if arch(x86_64) || arch(i386)

typealias MachineBreakpointState = BreakpointStateX86_64

struct BreakpointStateX86_64 {
    // Original code byte instead of INT 3.
    let originalByte: UInt8

    private init(originalByte: UInt8) {
        self.originalByte = originalByte
    }

    func restoreOriginalInstruction(at address: Address) {
        UnsafeMutablePointer<UInt8>(bitPattern: address.bitPattern)!.pointee = originalByte
    }

    static func create(at address: Address) -> (MachineBreakpointState, landingAddress: Address) {
        let bytes = UnsafeMutablePointer<UInt8>(bitPattern: address.bitPattern)!
        let result = MachineBreakpointState(originalByte: bytes.pointee)
        bytes.pointee = UInt8(0xCC) // INT 3.
        return (result, landingAddress: Address(bitPattern: address.bitPattern + 1))
    }

    // The number of bytes that have to be modified after the address in order to install a breakpoint.
    static var numberOfBytesToPatch: UInt {
        return 1
    }
}

#endif
