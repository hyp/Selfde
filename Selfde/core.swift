//
//  core.swift
//  Selfde
//

import Foundation

public typealias ThreadID = UInt64

public struct Breakpoint {
    // Breakpoint's address.
    public let address: OpaquePointer

    public init(address: OpaquePointer) {
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
