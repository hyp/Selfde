//
//  debugger.swift
//  Selfde
//

public enum MemoryReadResult {
    case Bytes(UnsafeBufferPointer<UInt8>)
}

public enum ThreadReference {
    case ID(ThreadID) // NNN
    case Any          // 0
    case All          // -1
}

public enum ThreadResumeAction: Int {
    case None
    case Stop
    case Continue
    case Step
}

public struct ThreadResumeEntry {
    public let thread: ThreadReference
    public let action: ThreadResumeAction
    public let address: COpaquePointer?
}

public enum ProcessResumeAction {
    case ResumeThreads(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction)
    case Exit
}

public struct ThreadStopInfo {
    public let signalNumber: UInt8
    public let dispatchQueueAddress: COpaquePointer?
    public struct MachInfo {
        let exceptionType: Int
        let exceptionData: [UInt]

        public init(exceptionType: Int, exceptionData: [UInt]) {
            self.exceptionType = exceptionType
            self.exceptionData = exceptionData
        }
    }
    public let machInfo: MachInfo?

    public init(signalNumber: UInt8, dispatchQueueAddress: COpaquePointer?, machInfo: MachInfo?) {
        self.signalNumber = signalNumber
        self.dispatchQueueAddress = dispatchQueueAddress
        self.machInfo = machInfo
    }
}

public protocol Debugger: class {
    var registerContextSize: Int { get }

    var primaryThreadID: ThreadID { get }
    var threads: [ThreadID] { get }

    func attach(processID: Int) throws
    func getSharedLibraryInfoAddress() throws -> COpaquePointer

    func getStopInfoForThread(threadID: ThreadID) throws -> ThreadStopInfo
    func isThreadAlive(threadID: ThreadID) throws -> Bool

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
