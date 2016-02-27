//
//  debugger.swift
//  Selfde
//

// Read/Write/Execute memory permissions.
struct MemoryPermissions: OptionSetType {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = 0 }
    
    static let Read = MemoryPermissions(rawValue: 1)
    static let Write = MemoryPermissions(rawValue: 2)
    static let Execute = MemoryPermissions(rawValue: 4)
}

enum MemoryReadResult {
    case Bytes(UnsafeBufferPointer<UInt8>)
}

enum ThreadReference {
    case ID(UInt) // NNN
    case Any      // 0
    case All      // -1
}

enum ThreadResumeAction: Int {
    case Stop
    case Continue
    case Step
}

protocol Debugger: class {
    var registerContextSize: Int { get }

    var primaryThreadID: UInt { get }

    func killInferior() throws
    func getSharedLibraryInfoAddress() throws -> COpaquePointer

    func resume(thread: ThreadReference, action: ThreadResumeAction, defaultAction: ThreadResumeAction, address: COpaquePointer?) throws

    // TODO: ref count up
    func setBreakpoint(address: COpaquePointer, byteSize: Int) throws
    func removeBreakpoint(address: COpaquePointer) throws

    func getRegisterValueForThread(threadID: UInt, registerID: UInt32, registerSetID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterValueForThread(threadID: UInt, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws

    func getRegisterContextForThread(threadID: UInt, inout dest: [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterContextForThread(threadID: UInt, source: ArraySlice<UInt8>) throws

    func allocate(size: Int, permissions: MemoryPermissions) throws -> COpaquePointer
    func deallocate(address: COpaquePointer) throws
    
    func readMemory(address: COpaquePointer, size: Int) throws -> MemoryReadResult
    func writeMemory(address: COpaquePointer, bytes: [UInt8]) throws
}
