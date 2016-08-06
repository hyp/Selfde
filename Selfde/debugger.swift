//
//  debugger.swift
//  Selfde
//

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
    public let address: Address?
}

public enum ProcessResumeAction {
    case resumeThreads(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction)
    case exit
}

public struct ThreadStopInfo {
    public let signalNumber: UInt8
    public let dispatchQueueAddress: Address?
    public struct MachInfo {
        let exceptionType: Int
        let exceptionData: [UInt]

        public init(exceptionType: Int, exceptionData: [UInt]) {
            self.exceptionType = exceptionType
            self.exceptionData = exceptionData
        }
    }
    public let machInfo: MachInfo?

    public init(signalNumber: UInt8, dispatchQueueAddress: Address?, machInfo: MachInfo?) {
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
    func getSharedLibraryInfoAddress() throws -> Address

    func interruptExecution() throws

    func detach()

    func getStopInfoForThread(_ threadID: ThreadID) throws -> ThreadStopInfo
    func isThreadAlive(_ threadID: ThreadID) throws -> Bool

    func setBreakpoint(_ address: Address, byteSize: Int) throws
    func removeBreakpoint(_ address: Address) throws

    // Instruction Pointer/Program counter.
    func getIPRegisterValueForThread(_ threadID: ThreadID) throws -> Address

    func getRegisterValueForThread(_ threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, dest: inout [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterValueForThread(_ threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws

    func getRegisterContextForThread(_ threadID: ThreadID, dest: inout [UInt8]) throws -> ArraySlice<UInt8>
    func setRegisterContextForThread(_ threadID: ThreadID, source: ArraySlice<UInt8>) throws

    func allocate(_ size: Int, permissions: MemoryPermissions) throws -> Address
    func deallocate(_ address: Address) throws

    func readMemory(_ address: Address, size: Int) throws -> MemoryReadResult
    func writeMemory(_ address: Address, bytes: [UInt8]) throws
}
