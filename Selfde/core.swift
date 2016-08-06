//
//  core.swift
//  Selfde
//

import Foundation

public typealias ThreadID = UInt64

public struct Address: Equatable, Hashable {
    // In-process, thus same width.
    public let bitPattern: UInt

    public init(bitPattern: UInt) {
        self.bitPattern = bitPattern
    }
    public var hashValue: Int {
        return bitPattern.hashValue
    }
}

public func == (lhs: Address, rhs: Address) -> Bool {
    return lhs.bitPattern == rhs.bitPattern
}

#if arch(x86_64)

public extension Address {
    init(bitPattern64: UInt64) {
        bitPattern = UInt(bitPattern64)
    }

    var bitPattern64: UInt64 {
        return UInt64(bitPattern)
    }
}

#endif

public struct Breakpoint {
    // Breakpoint's address.
    public let address: Address

    public init(address: Address) {
        self.address = address
    }
}

// Read/Write/Execute memory permissions.
public struct MemoryPermissions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let read = MemoryPermissions(rawValue: 1)
    public static let write = MemoryPermissions(rawValue: 2)
    public static let execute = MemoryPermissions(rawValue: 4)
}

// Thread's run state.
public enum RunState {
    case running
    case stopped
    case waiting
    case uninterruptible
    case halted
}

public enum MemoryReadResult {
    case bytes(UnsafeBufferPointer<UInt8>)
}
