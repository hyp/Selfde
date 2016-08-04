//
//  debugger.swift
//  Selfde
//

public enum MemoryReadResult {
    case bytes(UnsafeBufferPointer<UInt8>)
}

public enum ThreadReference {
    case id(ThreadID) // NNN
    case any          // 0
    case all          // -1
}

public enum ThreadResumeAction: Int {
    case none
    case stop
    case `continue`
    case step
}

public struct ThreadResumeEntry {
    public let thread: ThreadReference
    public let action: ThreadResumeAction
    public let address: OpaquePointer?
}

public enum ProcessResumeAction {
    case resumeThreads(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction)
    case exit
}

public struct ThreadStopInfo {
    public let signalNumber: UInt8
    public let dispatchQueueAddress: OpaquePointer?
    public struct MachInfo {
        let exceptionType: Int
        let exceptionData: [UInt]

        public init(exceptionType: Int, exceptionData: [UInt]) {
            self.exceptionType = exceptionType
            self.exceptionData = exceptionData
        }
    }
    public let machInfo: MachInfo?

    public init(signalNumber: UInt8, dispatchQueueAddress: OpaquePointer?, machInfo: MachInfo?) {
        self.signalNumber = signalNumber
        self.dispatchQueueAddress = dispatchQueueAddress
        self.machInfo = machInfo
    }
}

public protocol Debugger: class {
    var registerContextSize: Int { get }

    var primaryThreadID: ThreadID { get }
    var threads: [ThreadID] { get }

    func attach(_ processID: Int) throws
    func getSharedLibraryInfoAddress() throws -> OpaquePointer

    func interruptExecution() throws

    func detach()

    func getStopInfoForThread(_ threadID: ThreadID) throws -> ThreadStopInfo
    func isThreadAlive(_ threadID: ThreadID) throws -> Bool

    func setBreakpoint(_ address: OpaquePointer, byteSize: Int) throws
    func removeBreakpoint(_ address: OpaquePointer) throws

    // Instruction Pointer/Program counter.
    func getIPRegisterValueForThread(_ threadID: ThreadID) throws -> OpaquePointer

    func getRegisterValueForThread(_ threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterValueForThread(_ threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws

    func getRegisterContextForThread(_ threadID: ThreadID, dest: inout [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterContextForThread(_ threadID: ThreadID, source: ArraySlice<UInt8>) throws

    func allocate(_ size: Int, permissions: MemoryPermissions) throws -> OpaquePointer
    func deallocate(_ address: OpaquePointer) throws

    func readMemory(_ address: OpaquePointer, size: Int) throws -> MemoryReadResult
    func writeMemory(_ address: OpaquePointer, bytes: [UInt8]) throws
}
