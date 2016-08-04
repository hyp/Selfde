//
//  debugServer.swift
//  Selfde
//

import Foundation

public protocol DebugServerLogger: class {
    func log(_ message: String)

    func debugServerDidReceiveBinaryPacket(_ packet: ArraySlice<UInt8>)
    func debugServerDidReceivePacket(_ packet: String)

    func debugServerDidSendBinaryPacket(_ packet: ArraySlice<UInt8>)
    func debugServerDidSendPacket(_ packet: String)
}

enum ErrorResultKind {
    case e01
    case e08
    case e09
    case e16
    case e25
    case e32
    case e44
    case e45
    case e47
    case e49
    case e51
    case e53
    case e54
    case e55
    case e68
    case e74
    case e75
    case e77
}

enum ResponseResult {
    case none
    case ok
    case response(String)
    case binaryResponse([UInt8])
    case threadStopReply
    case stopReplyForThread(ThreadID)
    case unimplemented
    case invalid(String)
    case error(ErrorResultKind)
    case resume(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction)
    case exit(String?)
}

struct DebugServerState {
    let debugger: Debugger
    var registerState: DebuggerRegisterState
    private var processID: Int?

    private var continueThread = ThreadReference.all
    private var currentThread = ThreadReference.all

    private var currentThreadID: ThreadID {
        switch currentThread {
        case .id(let id):
            return id
        case .any, .all:
            return debugger.primaryThreadID
        }
    }

    private var continueThreadID: ThreadID {
        switch continueThread {
        case .id(let id):
            return id
        case .any, .all:
            return currentThreadID
        }
    }

    // Should we send/check for ACK/NACKs and worry about the checksum?
    private var noAckMode = false
    // Can commands like 'g' include the thread id?
    private var threadSuffixSupported = false
    private var listThreadsInStopReply = false

    private(set) weak var logger: DebugServerLogger?

    init(debugger: Debugger, logger: DebugServerLogger?) {
        self.debugger = debugger
        self.registerState = DebuggerRegisterState(debugger: debugger)
        self.logger = logger
    }
}

extension PacketParser {
    private mutating func consumeThreadID() -> ThreadID? {
        guard let value = consumeHexUInt64() else {
            return nil
        }
        return ThreadID(value)
    }
}

extension DebugServerState {
    // Extracts the 'thread:NNN' suffix or returns the current thread ID.
    mutating func extractThreadID(_ payload: String) -> ThreadID? {
        guard threadSuffixSupported else {
            return currentThreadID
        }
        guard let range = payload.range(of: "thread:") else {
            return nil
        }
        var parser = PacketParser(payload: payload, offset: range.upperBound)
        return parser.consumeThreadID()
    }
}

// packet '?'
private func handleHaltReasonQuery(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    return .threadStopReply
}

private func handleK(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    // Exit with code 9 (KILL).
    return .exit("X09")
}

// D packets detach the server from the process.
private func handleD(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    return .exit("OK")
}

// m packets read memory.
private func handleMemoryRead(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .invalid("Missing size")
    }
    guard size != 0 else {
        return .response("")
    }
    do {
        switch try server.debugger.readMemory(address, size: Int(size)) {
        case .bytes(let buffer):
            return .response(buffer.hexString)
        }
    } catch {
        return .error(.e08)
    }
}

// M packets write memory.
private func handleMemoryWrite(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .invalid("Missing size")
    }
    guard size != 0 else {
        return .ok
    }
    guard parser.consumeIfPresent(UnicodeScalar(":")) else {
        return .invalid("Missing colon")
    }
    guard let bytes = parser.readHexBytes() else {
        return .invalid("Invalid hex bytes")
    }
    guard bytes.count == Int(size) else {
        return .error(.e09)
    }
    do {
        try server.debugger.writeMemory(address, bytes: bytes)
        return .ok
    } catch {
        return .error(.e09)
    }
}

// x packets read memory and send it using a binary format.
private func handleBinaryMemoryRead(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .invalid("Missing size")
    }
    guard size != 0 else {
        return .ok
    }
    do {
        switch try server.debugger.readMemory(address, size: Int(size)) {
        case .bytes(let buffer):
            return .binaryResponse(buffer.encodedBinaryData)
        }
    } catch {
        return .error(.e08)
    }
}

// X packets write memory using binary data.
private func handleBinaryMemoryWrite(_ server: inout DebugServerState, payload: [UInt8]) -> ResponseResult {
    // Have to extract the string command.
    guard let colonPosition = payload.index(of: UInt8(ascii: ":")) else {
        return .invalid("Missing colon")
    }
    let bytes = payload.suffix(from: colonPosition + 1).decodedBinaryData
    var command = ""
    for byte in payload[0...colonPosition] {
        UnicodeScalar(byte).write(to: &command)
    }
    var parser = PacketParser(payload: command, offset: 1)
    guard let address = parser.consumeAddress() else {
        return .invalid("Missing address")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma")
    }
    guard let size = parser.consumeHexUInt() else {
        return .invalid("Missing size")
    }
    guard size != 0 else {
        return .ok
    }
    guard parser.consumeIfPresent(UnicodeScalar(":")) else {
        return .invalid("Missing colon")
    }
    guard bytes.count == Int(size) else {
        return .error(.e09)
    }
    do {
        try server.debugger.writeMemory(address, bytes: bytes)
        return .ok
    } catch {
        return .error(.e09)
    }
}

// _M packets allocate memory with permissions (useful for JIT).
private func handleAllocate(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 2)
    guard let size = parser.consumeHexUInt() else {
        return .invalid("Missing size")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma")
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
            return .error(.e53)
        }
    }
    do {
        let address = try server.debugger.allocate(Int(size), permissions: permissions)
        return .response(address.bigEndianHexString)
    } catch {
        return .error(.e53)
    }
}

// _m packets deallocate memory that was allocated using _M.
private func handleDeallocate(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 2)
    guard let address = parser.consumeAddress() else {
        return .error(.e54)
    }
    do {
        try server.debugger.deallocate(address)
        return .ok
    } catch {
        return .error(.e54)
    }
}

private enum ValueResponseResult<T> {
    case none(ResponseResult)
    case some(T)
}

extension PacketParser {
    private mutating func parseThreadReference() -> ValueResponseResult<ThreadReference> {
        if consumeIfPresent("-") {
            guard consumeIfPresent("1") else {
                return .none(.invalid("Invalid thread number"))
            }
            return .some(.all)
        } else {
            guard let threadID = consumeThreadID() else {
                return .none(.invalid("Invalid thread number"))
            }
            return .some(threadID == 0 ? .any : .id(threadID))
        }
    }
}

// H packets select the current thread.
// -1: All, 0: Any, NNN: Thread ID.
private func handleSetCurrentThread(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let type = parser.consumeCharacter(), type == "c" || type == "g" else {
        return .invalid("Missing type")
    }
    let thread: ThreadReference
    switch parser.parseThreadReference() {
    case .some(let t):
        thread = t
    case .none(let parseResult):
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
    return .ok
}

// Return the current thread ID for qC packets.
private func handleCurrentThreadQuery(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    let threadID = server.currentThreadID
    // Set the current thread as well to override the .Any and .All states.
    server.currentThread = .id(threadID)
    return .response("QC\(String(threadID, radix: 16, uppercase: false))")
}

// T - is the thread alive?
private func handleThreadStatus(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let threadID = parser.consumeThreadID() else {
        return .invalid("No thread id given")
    }
    do {
        guard try server.debugger.isThreadAlive(threadID) else {
            return .error(.e16)
        }
        return .ok
    } catch {
        return .error(.e16)
    }
}

// qThreadStopInfo - info about a thread stop.
private func handleQThreadStopInfo(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "qThreadStopInfo".characters.count)
    guard let threadID = parser.consumeThreadID() else {
        return .invalid("No thread id given")
    }
    return .stopReplyForThread(threadID)
}

// vCont?
private func handleVContQuery(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    // Support 'c' (continue) and 's' (step)
    return .response("vCont;c;s")
}

// vCont
private func handleVCont(_ server: inout DebugServerState, payload: String) -> ResponseResult {
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
            action = .continue
        case "s"?:
            action = .step
        default:
            return .invalid("Unsupported vCont action")
        }
        if parser.consumeIfPresent(":") {
            switch parser.parseThreadReference() {
            case .some(let thread):
                actions.append(ThreadResumeEntry(thread: thread, action: action, address: .none))
            case .none(let parseResult):
                return parseResult
            }
        } else {
            guard defaultAction == nil else {
                return .invalid("Default action is specified more than once")
            }
            defaultAction = action
        }
    }
    guard defaultAction != nil || !actions.isEmpty else {
        return .invalid("No action specified")
    }
    // The response will be the stopped/exited message.
    return .resume(actions: actions, defaultAction: defaultAction ?? .stop)
}

// c [addr]
private func handleContinue(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    let address: Address?
    if parser.hasContents {
        guard let addr = parser.consumeAddress() else {
            return .invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    // Don't send an OK as the response is the stopped/exited message.
    return .resume(actions: [ ThreadResumeEntry(thread: server.continueThread, action: .continue, address: address) ], defaultAction: .continue)
}

// s [addr]
private func handleStep(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    let address: Address?
    if parser.hasContents {
        guard let addr = parser.consumeAddress() else {
            return .invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    // Don't send an OK as the response is the stopped/exited message.
    return .resume(actions: [ ThreadResumeEntry(thread: .id(server.continueThreadID), action: .step, address: address) ], defaultAction: .stop)
}

// z/Z packets control the breakpoints/watchpoints.
private func handleZ(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload)
    guard let command = parser.consumeCharacter(),
        let breakpointType = parser.consumeCharacter() else {
            return .invalid("")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma separator")
    }
    guard let address = parser.consumeAddress() else {
        return .invalid("Invalid address")
    }
    guard parser.consumeComma() else {
        return .invalid("Missing comma separator")
    }
    guard let byteSize = parser.consumeHexUInt() else {
        return .invalid("Invalid byte size / kind")
    }
    
    guard breakpointType == "0" else {
        // Not a software breakpoint.
        // Could be a hardware breakpoint(1) or watchpoint (2,3,4), but they're not implemented.
        return .unimplemented
    }
    switch command {
    case "Z":
        do {
            try server.debugger.setBreakpoint(address, byteSize: Int(byteSize))
            return .ok
        } catch {
            return .error(.e09)
        }
    case "z":
        do {
            try server.debugger.removeBreakpoint(address)
            return .ok
        } catch {
            return .error(.e08)
        }
    default:
        break
    }
    return .unimplemented
}

private func handleQShlibInfoAddr(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    do {
        let address = try server.debugger.getSharedLibraryInfoAddress()
        return .response(address.bigEndianHexString)
    } catch {
        return .error(.e44)
    }
}

private func handleQSymbol(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    // Don't need any symbol lookups.
    return .ok
}

private func handleQSupported(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    // Don't care about the payload here.
    return .response("PacketSize=20000;qEcho+")
}

// This will enabled thread suffix for the 'g', 'G', 'p', and 'P' commands.
private func handleQThreadSuffixSupported(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    server.threadSuffixSupported = true
    return .ok
}

// This will enable thread information in the stop reply packet.s
private func handleQListThreadsInStopReply(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    server.listThreadsInStopReply = true
    return .ok
}

// Returns host information.
private func handleQHostInfo(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    return .response(getHostProcessInfo())
}

private func getHostProcessInfo(isHostInfo: Bool = true) -> String {
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
        result.write("ptrsize:\(sizeof(OpaquePointer.self));")
    } else {
        result.write("ptrsize:\(String(sizeof(OpaquePointer.self), radix: 16, uppercase: false))")
    }
    return result
}

private func getCPUType(isHostInfo: Bool) -> (Int, Int)? {
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
private func handleQProcessInfo(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var result = ""
    guard let processID = server.processID else {
        return .error(.e68)
    }
    result += "pid:\(String(processID, radix: 16, uppercase: false));"

    var processInfoRequest = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(processID)]
    var processInfo = kinfo_proc()
    var processInfoSize = sizeofValue(processInfo)
    if processInfoRequest.withUnsafeMutableBufferPointer({ (requestPtr: inout UnsafeMutableBufferPointer<Int32>) in
        withUnsafeMutablePointer(&processInfo) { infoPtr in
            sysctl(requestPtr.baseAddress, 4, infoPtr, &processInfoSize, nil, 0)
        }
    }) == 0 && processInfoSize > 0 {
        func hex(_ i: UInt32) -> String {
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
    return .response(result)
}

private func handleQEcho(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    // Send back the payload.
    return .response(payload)
}

// vAttach
// Note: vAttachOrWait, vAttachName, vAttachWait aren't supported.
private func handleVAttach(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "vAttach;".characters.count)
    guard let processID = parser.consumeHexUInt() else {
        return .invalid("No PID given")
    }
    do {
        server.processID = Int(processID)
        try server.debugger.attach(Int(processID))
        // Send a stop reply packet.
        return .threadStopReply
    } catch {
        // E01 is the attachment failure error.
        return .error(.e01)
    }
}

// Implements a debug server that's partially compatible with the GDB remote protocol and supports a couple of LLDB extensions.
// GDB protocol reference:    https://sourceware.org/gdb/onlinedocs/gdb/Remote-Protocol.html
// LLDB extensions reference: <LLDB repository>/docs/lldb-gdb-remote.txt
public class DebugServer {
    private var state: DebugServerState
    private let writer: RemoteDebuggingWriter
    private var handlers: [(String, (inout DebugServerState, String) -> ResponseResult)]

    public init(debugger: Debugger, writer: RemoteDebuggingWriter, logger: DebugServerLogger? = nil) {
        state = DebugServerState(debugger: debugger, logger: logger)
        self.writer = writer
        handlers = []
        handlers = [
            ("?", handleHaltReasonQuery),
            ("m", handleMemoryRead),
            ("M", handleMemoryWrite),
            ("x", handleBinaryMemoryRead),
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
            ("QSaveRegisterState", handleQSaveRegisterState),
            ("QRestoreRegisterState:", handleQRestoreRegisterState),
            ("QStartNoAckMode", { [unowned self] server, payload in
                // Send OK before changing the flag.
                do {
                    try self.sendResponse(.ok)
                } catch {
                    return .exit(nil)
                }
                server.noAckMode = true
                return .none
            }),
            ("qEcho:", handleQEcho),
            ("k", handleK),
            ("D", handleD)
        ]
    }

    func handlePacketPayload(_ payload: String) -> ResponseResult {
        for handler in handlers {
            if payload.hasPrefix(handler.0) {
                return handler.1(&state, payload)
            }
        }
        return .unimplemented
    }

    func handleBinaryPacketPayload(_ payload: [UInt8]) -> ResponseResult {
        guard let first = payload.first, first == UInt8(ascii: "X") else {
            return .unimplemented
        }
        return handleBinaryMemoryWrite(&state, payload: payload)
    }

    private func handleStopReplyForThread(_ threadID: ThreadID) -> ResponseResult {
        let info: ThreadStopInfo
        do {
            info = try state.debugger.getStopInfoForThread(threadID)
        } catch {
            return .error(.e51)
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
            for (i, threadID) in threads.enumerated() {
                if i > 0 { result += "," }
                result += String(threadID, radix: 16, uppercase: false)
            }
            result += ";"
            do {
                var output = ""
                for (i, threadID) in threads.enumerated() {
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
            state.logger?.log("Failed to emit register info in stop reply")
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
        return .response(result)
    }

    func handleStopReply(_ result: ResponseResult) -> ResponseResult {
        switch result {
        case .threadStopReply:
            let threadID = state.debugger.primaryThreadID
            state.currentThread = .id(threadID)
            return handleStopReplyForThread(threadID)
        case .stopReplyForThread(let threadID):
            return handleStopReplyForThread(threadID)
        default:
            assertionFailure("Invalid stop reply")
            return .none
        }
    }

    private func sendResponse(_ result: ResponseResult) throws {
        switch result {
        case .none:
            break
        case .ok:
            try send("OK")
        case .response(let r):
            try send(r)
        case .binaryResponse(let bytes):
            try send(bytes)
        case .threadStopReply, .stopReplyForThread:
            try sendResponse(handleStopReply(result))
        case .unimplemented:
            try send("")
        case .invalid:
            try send("E03")
        case .error(let kind):
            try send("\(kind)".uppercased())
        case .resume, .exit:
            assertionFailure("Invalid response")
        }
    }

    private func sendOutput(_ output: inout [UInt8]) throws {
        guard !state.noAckMode else {
            output.append(contentsOf: "#00".utf8)
            try writer.write(data: output[0..<output.count])
            return
        }
        // Compute the checksum.
        let checksum = output[1..<output.count].checksum
        output.append(contentsOf: "#\([checksum].hexString)".utf8)
        try writer.write(data: output[0..<output.count])
    }

    private func send(_ payload: String) throws {
        var output = [UInt8]()
        output.reserveCapacity(1024)
        output.append(UInt8(ascii: "$"))
        output.append(contentsOf: payload.utf8)
        try sendOutput(&output)
        state.logger?.debugServerDidSendPacket(payload)
    }

    private func send(_ payload: [UInt8]) throws {
        var output = [UInt8]()
        output.reserveCapacity(payload.count + 4)
        output.append(UInt8(ascii: "$"))
        output.append(contentsOf: payload)
        try sendOutput(&output)
        state.logger?.debugServerDidSendBinaryPacket(payload[0..<payload.count])
    }

    private func sendACK() throws {
        let data = [UInt8(ascii: "+")]
        try writer.write(data: data[0..<data.count])
    }

    private func sendNACK() throws {
        let data = [UInt8(ascii: "-")]
        try writer.write(data: data[0..<data.count])
    }

    /// Processes incoming packets until all of the received data is exhausted or a resume or an exit packet like 'c'/'k' is reached.
    public func processPacketsUntilResumeOrExit(_ receivedData: ArraySlice<UInt8>) throws -> ProcessResumeAction? {
        var done = false
        while !done {
            let packets: [RemoteDebuggingPacket]
            if let savedPackets = self.savedPackets {
                assert(!savedPackets.isEmpty)
                packets = savedPackets
                self.savedPackets = nil
            } else {
                let data = receivedData
                done = true
                packets = parsePackets(&partialData, newData: data, checkChecksums: !state.noAckMode)
            }
            for (i, packet) in packets.enumerated() {
                let response: ResponseResult
                switch packet {
                case .payload(let payload):
                    if !state.noAckMode {
                        try sendACK()
                    }
                    response = handlePacketPayload(payload)
                    state.logger?.debugServerDidReceivePacket(payload)
                case .binaryPayload(let bytes):
                    if !state.noAckMode {
                        try sendACK()
                    }
                    response = handleBinaryPacketPayload(bytes)
                    state.logger?.debugServerDidReceiveBinaryPacket(bytes[0..<bytes.count])
                case .ack, .nack: // Don't resend on NACKs..
                    continue
                case .interrupt:
                    state.logger?.debugServerDidReceivePacket("<Interrupt>")
                    try state.debugger.interruptExecution()
                    response = .threadStopReply
                case .invalidPacket, .invalidChecksum:
                    try sendNACK()
                    continue
                }
                switch response {
                case .resume(let actions, let defaultAction):
                    // Save the next packets if there are any (unlikely).
                    let remainingPackets = packets[(i+1)..<packets.count]
                    if !remainingPackets.isEmpty {
                        for packet in remainingPackets {
                            if case .interrupt = packet {
                                state.logger?.log("Found an interrupt packet that can't be gracefully handled; assuming an exit.")
                                state.debugger.detach()
                                return .exit
                            }
                        }
                        savedPackets = Array(remainingPackets)
                    }
                    return .resumeThreads(actions: actions, defaultAction: defaultAction)
                case .exit(let response?):
                    state.debugger.detach()
                    try sendResponse(.response(response))
                    return .exit
                case .exit:
                    state.debugger.detach()
                    return .exit
                case let result:
                    try sendResponse(result)
                }
            }
        }
        return nil
    }

    public func sendStopReply() throws {
        return try sendResponse(.threadStopReply)
    }

    public func sendExitReply() throws {
        return try sendResponse(.response("X00"))
    }

    private var savedPackets: [RemoteDebuggingPacket]?
    private var partialData = [UInt8]()
}
