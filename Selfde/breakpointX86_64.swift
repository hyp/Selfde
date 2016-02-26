//
//  breakpointX86_64.swift
//  Selfde
//

typealias MachineBreakpointState = BreakpointStateX86_64

struct BreakpointStateX86_64 {
    // Original code byte instead of INT 3.
    let originalByte: UInt8

    private init(originalByte: UInt8) {
        self.originalByte = originalByte
    }

    func restoreOriginalInstruction(address: COpaquePointer) {
        UnsafeMutablePointer<UInt8>(address).memory = originalByte
    }

    static func create(address: COpaquePointer) -> (MachineBreakpointState, expectedHitAddress: COpaquePointer) {
        let bytes = UnsafeMutablePointer<UInt8>(address)
        let result = MachineBreakpointState(originalByte: bytes.memory)
        bytes.memory = UInt8(0xCC) // INT 3.
        return (result, COpaquePointer(bitPattern: unsafeBitCast(address, UInt.self) + 1))
    }

    // The number of bytes that have to be modified after the address in order to install a breakpoint.
    static var numberOfBytesToPatch: UInt {
        return 1
    }
}
