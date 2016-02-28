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

typealias ThreadID = UInt64

enum ThreadReference {
    case ID(ThreadID) // NNN
    case Any          // 0
    case All          // -1
}

enum ThreadResumeAction: Int {
    case None
    case Stop
    case Continue
    case Step
}

struct ThreadResumeEntry {
    let thread: ThreadReference
    let action: ThreadResumeAction
    let address: COpaquePointer?
}

struct ThreadStopInfo {
    let signalNumber: UInt8
    let dispatchQueueAddress: COpaquePointer?
    struct MachInfo {
        let exceptionType: Int
        let exceptionData: [UInt]
    }
    let machInfo: MachInfo?
}

protocol Debugger: class {
    var registerContextSize: Int { get }

    var primaryThreadID: ThreadID { get }
    var threads: [ThreadID] { get }

    func attach(processID: Int) throws
    func killInferior() throws
    func getSharedLibraryInfoAddress() throws -> COpaquePointer

    func resume(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction) throws
    func getStopInfoForThread(threadID: ThreadID) throws -> ThreadStopInfo

    // TODO: ref count up
    func setBreakpoint(address: COpaquePointer, byteSize: Int) throws
    func removeBreakpoint(address: COpaquePointer) throws

    // Instruction Pointer/Program counter.
    func getIPRegisterValueForThread(threadID: ThreadID) throws -> COpaquePointer

    func getRegisterValueForThread(threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterValueForThread(threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws

    func getRegisterContextForThread(threadID: ThreadID, inout dest: [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterContextForThread(threadID: ThreadID, source: ArraySlice<UInt8>) throws

    func allocate(size: Int, permissions: MemoryPermissions) throws -> COpaquePointer
    func deallocate(address: COpaquePointer) throws

    func readMemory(address: COpaquePointer, size: Int) throws -> MemoryReadResult
    func writeMemory(address: COpaquePointer, bytes: [UInt8]) throws
}
