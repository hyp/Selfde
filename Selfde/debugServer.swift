//
//  debugServer.swift
//  Selfde
//

import Foundation

enum ErrorResultKind {
    case E01
    case E08
    case E09
    case E16
    case E25
    case E32
    case E44
    case E45
    case E47
    case E49
    case E51
    case E53
    case E54
    case E55
    case E68
    case E74
}

enum ResponseResult {
    case None
    case OK
    case Response(String)
    case ThreadStopReply
    case StopReplyForThread(ThreadID)
    case Unimplemented
    case Invalid(String)
    case Error(ErrorResultKind)
    case Resume
    case Exit(String?)
}

struct DebugServerState {
    let debugger: Debugger
    var registerState: DebuggerRegisterState
    private var processID: Int?

    private var continueThread = ThreadReference.All
    private var currentThread = ThreadReference.All

    private var currentThreadID: ThreadID {
        switch currentThread {
        case .ID(let id):
            return id
        case .Any, .All:
            return debugger.primaryThreadID
        }
    }

    private var continueThreadID: ThreadID {
        switch continueThread {
        case .ID(let id):
            return id
        case .Any, .All:
            return currentThreadID
        }
    }

    // Should we send/check for ACK/NACKs and worry about the checksum?
    private var noAckMode = false
    // Can commands like 'g' include the thread id?
    private var threadSuffixSupported = false
    private var listThreadsInStopReply = false

    init(let debugger: Debugger) {
        self.debugger = debugger
        self.registerState = DebuggerRegisterState(debugger: debugger)
    }
}

extension DebugServerState {
    // Extracts the 'thread:NNN' suffix or returns the current thread ID.
    mutating func extractThreadID(payload: String) -> ThreadID? {
        guard threadSuffixSupported else {
            return currentThreadID
        }
        guard let range = payload.rangeOfString("thread:") else {
            return nil
        }
        var parser = PacketParser(payload: payload, offset: range.endIndex)
        guard let threadID = parser.consumeHexUInt() else {
            return nil
        }
        return ThreadID(threadID)
    }
}

// packet '?'
private func handleHaltReasonQuery(inout server: DebugServerState, payload: String) -> ResponseResult {
    return .ThreadStopReply
}

private func handleK(inout server: DebugServerState, payload: String) -> ResponseResult {
    do {
        try server.debugger.killInferior()
        // Exit with code 9 (KILL).
        return .Exit("X09")
    } catch {
        return .Exit(nil)
    }
}

// m packets read memory.
private func handleMemoryRead(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .Invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .Invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .Invalid("Missing size")
    }
    guard size != 0 else {
        return .Response("")
    }
    do {
        switch try server.debugger.readMemory(address, size: Int(size)) {
        case .Bytes(let buffer):
            return .Response(buffer.hexString)
        }
    } catch {
        return .Error(.E08)
    }
}

// M packets write memory.
private func handleMemoryWrite(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .Invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .Invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .Invalid("Missing size")
    }
    guard size != 0 else {
        return .OK
    }
    guard parser.consumeIfPresent(UnicodeScalar(":")) else {
        return .Invalid("Missing colon")
    }
    guard let bytes = parser.readHexBytes() else {
        return .Invalid("Invalid hex bytes")
    }
    guard bytes.count == Int(size) else {
        return .Error(.E09)
    }
    do {
        try server.debugger.writeMemory(address, bytes: bytes)
        return .OK
    } catch {
        return .Error(.E09)
    }
}

// _M packets allocate memory with permissions (useful for JIT).
private func handleAllocate(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 2)
    guard let size = parser.consumeHexUInt() else {
        return .Invalid("Missing size")
    }
    guard parser.consumeComma() else {
        return .Invalid("Missing comma")
    }
    var permissions: MemoryPermissions = []
    while let a = parser.consumeCharacter() {
        switch a {
        case "r":
            permissions.insert(.Read)
        case "w":
            permissions.insert(.Write)
        case "x":
            permissions.insert(.Execute)
        default:
            return .Error(.E53)
        }
    }
    do {
        let address = try server.debugger.allocate(Int(size), permissions: permissions)
        return .Response(address.bigEndianHexString)
    } catch {
        return .Error(.E53)
    }
}

// _m packets deallocate memory that was allocated using _M.
private func handleDeallocate(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 2)
    guard let address: COpaquePointer = parser.consumeAddress() else {
        return .Error(.E54)
    }
    do {
        try server.debugger.deallocate(address)
        return .OK
    } catch {
        return .Error(.E54)
    }
}

private enum ValueResponseResult<T> {
    case None(ResponseResult)
    case Some(T)
}

extension PacketParser {
    private mutating func parseThreadReference() -> ValueResponseResult<ThreadReference> {
        if consumeIfPresent("-") {
            guard consumeIfPresent("1") else {
                return .None(.Invalid("Invalid thread number"))
            }
            return .Some(.All)
        } else {
            guard let threadID = consumeHexUInt() else {
                return .None(.Invalid("Invalid thread number"))
            }
            return .Some(threadID == 0 ? .Any : .ID(ThreadID(threadID)))
        }
    }
}

// H packets select the current thread.
// -1: All, 0: Any, NNN: Thread ID.
private func handleSetCurrentThread(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let type = parser.consumeCharacter() where type == "c" || type == "g" else {
        return .Invalid("Missing type")
    }
    let thread: ThreadReference
    switch parser.parseThreadReference() {
    case .Some(let t):
        thread = t
    case .None(let parseResult):
        return parseResult
    }
    switch type {
    case "c":
        server.continueThread = thread
    case "g":
        server.currentThread = thread
    default:
        assertionFailure()
    }
    return .OK
}

// Return the current thread ID for qC packets.
private func handleCurrentThreadQuery(inout server: DebugServerState, payload: String) -> ResponseResult {
    let threadID = server.currentThreadID
    // Set the current thread as well to override the .Any and .All states.
    server.currentThread = .ID(threadID)
    return .Response("QC\(String(threadID, radix: 16, uppercase: false))")
}

// T - is the thread alive?
private func handleThreadStatus(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let threadID = parser.consumeHexUInt() else {
        return .Invalid("No thread id given")
    }
    do {
        guard try server.debugger.isThreadAlive(ThreadID(threadID)) else {
            return .Error(.E16)
        }
        return .OK
    } catch {
        return .Error(.E16)
    }
}

// qThreadStopInfo - info about a thread stop.
private func handleQThreadStopInfo(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "qThreadStopInfo".characters.count)
    guard let threadID = parser.consumeHexUInt() else {
        return .Invalid("No thread id given")
    }
    return .StopReplyForThread(ThreadID(threadID))
}

// vCont?
private func handleVContQuery(inout server: DebugServerState, payload: String) -> ResponseResult {
    // Support 'c' (continue) and 's' (step)
    return .Response("vCont;c;s")
}

// vCont
private func handleVCont(inout server: DebugServerState, payload: String) -> ResponseResult {
    if payload == "vCont;c" {
        return handleContinue(&server, payload: "c")
    } else if payload == "vCont;s" {
        return handleStep(&server, payload: "s")
    }
    var parser = PacketParser(payload: payload, offset: "vCont".characters.count)
    var actions: [ThreadResumeEntry] = []
    var defaultAction: ThreadResumeAction?
    while parser.consumeIfPresent(";") {
        let action: ThreadResumeAction
        switch parser.consumeCharacter() {
        case "c"?:
            action = .Continue
        case "s"?:
            action = .Step
        default:
            return .Invalid("Unsupported vCont action")
        }
        if parser.consumeIfPresent(":") {
            switch parser.parseThreadReference() {
            case .Some(let thread):
                actions.append(ThreadResumeEntry(thread: thread, action: action, address: .None))
            case .None(let parseResult):
                return parseResult
            }
        } else {
            guard defaultAction == nil else {
                return .Invalid("Default action is specified more than once")
            }
            defaultAction = action
        }
    }
    guard defaultAction != nil || !actions.isEmpty else {
        return .Invalid("No action specified")
    }
    do {
        try server.debugger.resume(actions, defaultAction: defaultAction ?? .Stop)
        // The response will be the stopped/exited message.
        return .Resume
    } catch {
        return .Error(.E25)
    }
}

// c [addr]
private func handleContinue(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    let address: COpaquePointer?
    if parser.hasContents {
        guard let addr = parser.consumeAddress() else {
            return .Invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    do {
        try server.debugger.resume([ ThreadResumeEntry(thread: server.continueThread, action: .Continue, address: address) ], defaultAction: .Continue)
        // Don't send an OK as the response is the stopped/exited message.
        return .Resume
    } catch {
        return .Error(.E25)
    }
}

// s [addr]
private func handleStep(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    let address: COpaquePointer?
    if parser.hasContents {
        guard let addr = parser.consumeAddress() else {
            return .Invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    do {
        // Make all other threads stop when we are stepping.
        try server.debugger.resume([ ThreadResumeEntry(thread: .ID(server.continueThreadID), action: .Step, address: address) ], defaultAction: .Stop)
        // Don't send an OK as the response is the stopped/exited message.
        return .Resume
    } catch {
        return .Error(.E49)
    }
}

// z/Z packets control the breakpoints/watchpoints.
private func handleZ(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload)
    guard let command = parser.consumeCharacter(),
        breakpointType = parser.consumeCharacter() else {
            return .Invalid("")
    }
    guard parser.consumeComma() else {
        return .Invalid("Missing comma separator")
    }
    guard let address = parser.consumeAddress() else {
        return .Invalid("Invalid address")
    }
    guard parser.consumeComma() else {
        return .Invalid("Missing comma separator")
    }
    guard let byteSize = parser.consumeHexUInt() else {
        return .Invalid("Invalid byte size / kind")
    }
    
    guard breakpointType == "0" else {
        // Not a software breakpoint.
        // Could be a hardware breakpoint(1) or watchpoint (2,3,4), but they're not implemented.
        return .Unimplemented
    }
    switch command {
    case "Z":
        do {
            try server.debugger.setBreakpoint(address, byteSize: Int(byteSize))
            return .OK
        } catch {
            return .Error(.E09)
        }
    case "z":
        do {
            try server.debugger.removeBreakpoint(address)
            return .OK
        } catch {
            return .Error(.E08)
        }
    default:
        break
    }
    return .Unimplemented
}

private func handleQShlibInfoAddr(inout server: DebugServerState, payload: String) -> ResponseResult {
    do {
        let address = try server.debugger.getSharedLibraryInfoAddress()
        return .Response(address.bigEndianHexString)
    } catch {
        return .Error(.E44)
    }
}

private func handleQSymbol(inout server: DebugServerState, payload: String) -> ResponseResult {
    // Don't need any symbol lookups.
    return .OK
}

private func handleQSupported(inout server: DebugServerState, payload: String) -> ResponseResult {
    // Don't care about the payload here.
    return .Response("PacketSize=20000;qEcho+")
}

// This will enabled thread suffix for the 'g', 'G', 'p', and 'P' commands.
private func handleQThreadSuffixSupported(inout server: DebugServerState, payload: String) -> ResponseResult {
    server.threadSuffixSupported = true
    return .OK
}

// This will enable thread information in the stop reply packet.s
private func handleQListThreadsInStopReply(inout server: DebugServerState, payload: String) -> ResponseResult {
    server.listThreadsInStopReply = true
    return .OK
}

// Returns host information.
private func handleQHostInfo(inout server: DebugServerState, payload: String) -> ResponseResult {
    return .Response(getHostProcessInfo())
}

private func getHostProcessInfo(isHostInfo isHostInfo: Bool = true) -> String {
    var result = ""
    if let (CPUType, CPUSubType) = getCPUType(isHostInfo: isHostInfo) {
        if isHostInfo {
            result.write("cputype:\(CPUType);cpusubtype:\(CPUSubType);")
        } else {
            result.write("cputype:\(String(CPUType, radix: 16, uppercase: false));cpusubtype:\(String(CPUSubType, radix: 16, uppercase: false));")
        }
    }
    #if os(OSX)
        result.write("ostype:macosx;")
        if isHostInfo {
            result.write("watchpoint_exceptions_received:after;")
        }
        result.write("vendor:apple;")
    #endif
    result.write("endian:little;") // FIXME: Any big endian targets?
    if isHostInfo {
        result.write("ptrsize:\(sizeof(COpaquePointer));")
    } else {
        result.write("ptrsize:\(String(sizeof(COpaquePointer), radix: 16, uppercase: false))")
    }
    return result
}

private func getCPUType(isHostInfo isHostInfo: Bool) -> (Int, Int)? {
    var type: UInt32 = 0
    var subtype: UInt32 = 0
    var is64BitCapable: UInt32 = 0
    var err: Int32 = withUnsafeMutablePointer(&type) {
        var size = sizeofValue(type)
        return sysctlbyname("hw.cputype", $0, &size, nil, 0)
    }
    err |= withUnsafeMutablePointer(&subtype) {
        var size = sizeofValue(subtype)
        return sysctlbyname("hw.cpusubtype", $0, &size, nil, 0)
    }
    if isHostInfo {
        // Host info decides on the 64 bit based on the hardware capability.
        err |= withUnsafeMutablePointer(&is64BitCapable) {
            var size = sizeofValue(is64BitCapable)
            return sysctlbyname("hw.cpu64bit_capable", $0, &size, nil, 0)
        }
        if is64BitCapable != 0 {
            type |= UInt32(CPU_ARCH_ABI64)
        }
    } else {
        // Process info decides on the 64 bit based on the target architecture, since we're debugging self.
        #if arch(x86_64) || arch(arm64)
            type |= UInt32(CPU_ARCH_ABI64)
        #endif
    }
    return err == 0 ? (Int(type), Int(subtype)) : nil
}

// Returns process information.
private func handleQProcessInfo(inout server: DebugServerState, payload: String) -> ResponseResult {
    var result = ""
    guard let processID = server.processID else {
        return .Error(.E68)
    }
    result += "pid:\(String(processID, radix: 16, uppercase: false));"

    var processInfoRequest = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(processID)]
    var processInfo = kinfo_proc()
    var processInfoSize = sizeofValue(processInfo)
    if processInfoRequest.withUnsafeMutableBufferPointer({ (inout requestPtr: UnsafeMutableBufferPointer<Int32>) in
        withUnsafeMutablePointer(&processInfo) { infoPtr in
            sysctl(requestPtr.baseAddress, 4, infoPtr, &processInfoSize, nil, 0)
        }
    }) == 0 && processInfoSize > 0 {
        func hex(i: UInt32) -> String {
            return String(Int(i), radix: 16, uppercase: false)
        }
        result += "parent-pid:\(String(Int(processInfo.kp_eproc.e_ppid), radix: 16, uppercase: false));"
        result += "real-uid:\(hex(processInfo.kp_eproc.e_pcred.p_ruid));"
        result += "real-gid:\(hex(processInfo.kp_eproc.e_pcred.p_rgid));"
        result += "effective-uid:\(hex(processInfo.kp_eproc.e_ucred.cr_uid));"
        if processInfo.kp_eproc.e_ucred.cr_ngroups > 0 {
            result += "effective-gid:\(hex(processInfo.kp_eproc.e_ucred.cr_groups.0));"
        }
    }
    result += getHostProcessInfo(isHostInfo: false)
    return .Response(result)
}

private func handleQEcho(inout server: DebugServerState, payload: String) -> ResponseResult {
    // Send back the payload.
    return .Response(payload)
}

// vAttach
// Note: vAttachOrWait, vAttachName, vAttachWait aren't supported.
private func handleVAttach(inout server: DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "vAttach;".characters.count)
    guard let processID = parser.consumeHexUInt() else {
        return .Invalid("No PID given")
    }
    do {
        server.processID = Int(processID)
        try server.debugger.attach(Int(processID))
        // Send a stop reply packet.
        return .ThreadStopReply
    } catch {
        // E01 is the attachment failure error.
        return .Error(.E01)
    }
}

// Implements a debug server that's partially compatible with the GDB remote protocol and supports a couple of LLDB extensions.
// GDB protocol reference:    https://sourceware.org/gdb/onlinedocs/gdb/Remote-Protocol.html
// LLDB extensions reference: <LLDB repository>/docs/lldb-gdb-remote.txt
public class DebugServer {
    private var state: DebugServerState
    private let connection: RemoteDebuggingConnection
    private var handlers: [(String, (inout DebugServerState, String) -> ResponseResult)]

    public init(debugger: Debugger, connection: RemoteDebuggingConnection) {
        state = DebugServerState(debugger: debugger)
        self.connection = connection
        handlers = []
        handlers = [
            ("?", handleHaltReasonQuery),
            ("m", handleMemoryRead),
            ("M", handleMemoryWrite),
            ("p", handleRegisterRead),
            ("P", handleRegisterWrite),
            ("g", handleGPRegistersRead),
            ("G", handleGPRegistersWrite),
            ("c", handleContinue),
            ("s", handleStep),
            ("z0", handleZ),
            ("Z0", handleZ),
            ("vCont?", handleVContQuery),
            ("vCont", handleVCont),
            ("vAttach;", handleVAttach),
            ("H", handleSetCurrentThread),
            ("qC", handleCurrentThreadQuery),
            ("T", handleThreadStatus),
            ("_M", handleAllocate),
            ("_m", handleDeallocate),
            ("qThreadStopInfo", handleQThreadStopInfo),
            ("qRegisterInfo", handleQRegisterInfo),
            ("qShlibInfoAddr", handleQShlibInfoAddr),
            ("qSymbol:", handleQSymbol),
            ("qSupported", handleQSupported),
            ("qHostInfo", handleQHostInfo),
            ("qProcessInfo", handleQProcessInfo),
            ("QThreadSuffixSupported", handleQThreadSuffixSupported),
            ("QListThreadsInStopReply", handleQListThreadsInStopReply),
            ("QStartNoAckMode", { [unowned self] server, payload in
                // Send OK before changing the flag.
                do {
                    try self.sendResponse(.OK)
                } catch {
                    return .Exit(nil)
                }
                server.noAckMode = true
                return .None
            }),
            ("qEcho:", handleQEcho),
            ("k", handleK)
        ]
    }

    func handlePacketPayload(payload: String) -> ResponseResult {
        for handler in handlers {
            if payload.hasPrefix(handler.0) {
                return handler.1(&state, payload)
            }
        }
        return .Unimplemented
    }

    private func handleStopReplyForThread(threadID: ThreadID) -> ResponseResult {
        let info: ThreadStopInfo
        do {
            info = try state.debugger.getStopInfoForThread(threadID)
        } catch {
            return .Error(.E51)
        }
        var result = "T"
        let signal = [info.signalNumber]
        result += signal.hexString
        result += "thread:\(String(threadID, radix: 16, uppercase: false));"
        // Dispatch Queue Address.
        if let address = info.dispatchQueueAddress {
            result += "qaddr:\(address.bigEndianHexString);"
        }
        // TODO: name/hexname?
        // Threads.
        if state.listThreadsInStopReply {
            let threads = state.debugger.threads
            result += "threads:"
            for (i, threadID) in threads.enumerate() {
                if i > 0 { result += "," }
                result += String(threadID, radix: 16, uppercase: false)
            }
            result += ";"
            do {
                var output = ""
                for (i, threadID) in threads.enumerate() {
                    if i > 0 { output += "," }
                    output += try state.debugger.getIPRegisterValueForThread(threadID).bigEndianHexString
                }
                result += "thread-pcs:\(output);"
            } catch {
            }
        }
        // Registers.
        do {
            try state.registerState.emitThreadStopInfoRegistersForThread(threadID, debugger: state.debugger, dest: &result)
        } catch {
            // TODO: Log
            print("Failed to emit register info in stop reply")
        }
        // Mach info.
        if let machInfo = info.machInfo {
            result += "metype:\(String(machInfo.exceptionType, radix: 16, uppercase: false));"
            result += "mecount:\(String(machInfo.exceptionData.count, radix: 16, uppercase: false));"
            for i in machInfo.exceptionData {
                result += "medata:\(String(i, radix: 16, uppercase: false));"
            }
        }
        // TODO: Support 'memory' for quicket backtracking?
        return .Response(result)
    }

    func handleStopReply(result: ResponseResult) -> ResponseResult {
        switch result {
        case .ThreadStopReply:
            let threadID = state.debugger.primaryThreadID
            state.currentThread = .ID(threadID)
            return handleStopReplyForThread(threadID)
        case .StopReplyForThread(let threadID):
            return handleStopReplyForThread(threadID)
        default:
            assertionFailure("Invalid stop reply")
            return .None
        }
    }

    private func sendResponse(result: ResponseResult) throws {
        switch result {
        case .None:
            break
        case .OK:
            try send("OK")
        case .Response(let r):
            try send(r)
        case .ThreadStopReply, .StopReplyForThread:
            try sendResponse(handleStopReply(result))
        case .Unimplemented:
            try send("")
        case .Invalid:
            try send("E03")
        case .Error(let kind):
            try send("\(kind)")
        case .Resume, .Exit:
            assertionFailure("Invalid response")
        }
    }

    private func send(payload: String) throws {
        var output = [UInt8]()
        output.reserveCapacity(1024)
        output.append(UInt8(ascii: "$"))
        output.appendContentsOf(payload.utf8)
        guard !state.noAckMode else {
            output.appendContentsOf("#00".utf8)
            try connection.write(output[0..<output.count])
            return
        }
        // Compute the checksum.
        let checksum = output[1..<output.count].checksum
        output.appendContentsOf("#\([checksum].hexString)".utf8)
        try connection.write(output[0..<output.count])
    }

    private func sendACK() throws {
        let data = [UInt8(ascii: "+")]
        try connection.write(data[0..<data.count])
    }

    private func sendNACK() throws {
        let data = [UInt8(ascii: "-")]
        try connection.write(data[0..<data.count])
    }

    /// Processes incoming packets until a resume or an exit packet like 'c'/'k' is reached.
    public func processPacketsUntilResumeOrExit() throws {
        while true {
            let packets: [RemoteDebuggingPacket]
            if let savedPackets = self.savedPackets {
                assert(!savedPackets.isEmpty)
                packets = savedPackets
                self.savedPackets = nil
            } else {
                let data = try connection.read()
                packets = parsePackets(&partialData, newData: data, checkChecksums: !state.noAckMode)
            }
            for (i, packet) in packets.enumerate() {
                switch packet {
                case .Payload(let payload):
                    if !state.noAckMode {
                        try sendACK()
                    }
                    switch handlePacketPayload(payload) {
                    case .Resume:
                        // Save the next packets if there are any (unlikely).
                        let remainingPackets = packets[(i+1)..<packets.count]
                        if !remainingPackets.isEmpty {
                            savedPackets = Array(remainingPackets)
                        }
                        return // Resume command.
                    case .Exit(let response?):
                        try sendResponse(.Response(response))
                        fallthrough
                    case .Exit:
                        return
                    case let result:
                        try sendResponse(result)
                    }
                case .ACK, .NACK: // Don't resend on NACKs..
                    break
                case .InvalidPacket, .InvalidChecksum:
                    try sendNACK()
                }
            }
        }
    }

    private var savedPackets: [RemoteDebuggingPacket]?
    private var partialData = [UInt8]()
}
