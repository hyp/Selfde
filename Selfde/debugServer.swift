//
//  debugServer.swift
//  Selfde
//

import Foundation

enum ErrorResultKind {
    case E08
    case E09
    case E25
    case E32
    case E44
    case E45
    case E47
    case E49
    case E53
    case E54
    case E55
    case E74
}

enum ParseResult {
    case NoReply
    case OK
    case Response(String)
    case Unimplemented
    case Invalid(String)
    case Error(ErrorResultKind)
}

struct DebugServerState {
    let debugger: Debugger
    var registerState: DebuggerRegisterState

    private var continueThread = ThreadReference.All
    private var currentThread = ThreadReference.All

    private var currentThreadID: UInt {
        switch currentThread {
        case .ID(let id):
            return id
        case .Any, .All:
            return debugger.primaryThreadID
        }
    }

    private var continueThreadID: UInt {
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
    mutating func extractThreadID(payload: String) -> UInt? {
        guard threadSuffixSupported else {
            return currentThreadID
        }
        guard let range = payload.rangeOfString("thread:") else {
            return nil
        }
        var parser = PacketLexer(payload: payload, offset: range.endIndex)
        guard let threadID = parser.expectAndConsumeHexBigEndianInteger() else {
            return nil
        }
        return threadID
    }
}

private func handleK(inout server: DebugServerState, payload: String) -> ParseResult {
    do {
        try server.debugger.killInferior()
        // Exit with code 9 (KILL).
        return .Response("X09")
    } catch {
    }
    return .NoReply
}

// m packets read memory.
private func handleMemoryRead(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload, offset: 1)
    guard let address = lexer.expectAndConsumeHexBigEndianAddress() else {
        return .Invalid("Missing address")
    }
    guard lexer.expectAndConsumeComma() else {
        return .Invalid("Missing comma")
    }
    guard let size = lexer.expectAndConsumeHexBigEndianInteger() else {
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
private func handleMemoryWrite(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload, offset: 1)
    guard let address = lexer.expectAndConsumeHexBigEndianAddress() else {
        return .Invalid("Missing address")
    }
    guard lexer.expectAndConsumeComma() else {
        return .Invalid("Missing comma")
    }
    guard let size = lexer.expectAndConsumeHexBigEndianInteger() else {
        return .Invalid("Missing size")
    }
    guard size != 0 else {
        return .OK
    }
    guard lexer.expectAndConsume(UnicodeScalar(":")) else {
        return .Invalid("Missing colon")
    }
    guard let bytes = lexer.readHexBytes() else {
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
private func handleAllocate(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload, offset: 2)
    guard let size = lexer.expectAndConsumeHexBigEndianInteger() else {
        return .Invalid("Missing size")
    }
    guard lexer.expectAndConsumeComma() else {
        return .Invalid("Missing comma")
    }
    var permissions: MemoryPermissions = []
    while let a = lexer.consumeCharacter() {
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
private func handleDeallocate(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload, offset: 2)
    guard let address: COpaquePointer = lexer.expectAndConsumeHexBigEndianAddress() else {
        return .Error(.E54)
    }
    do {
        try server.debugger.deallocate(address)
        return .OK
    } catch {
        return .Error(.E54)
    }
}

// H packets select the current thread.
// -1: All, 0: Any, NNN: Thread ID.
private func handleSetCurrentThread(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload, offset: 1)
    guard let type = lexer.consumeCharacter() where type == "c" || type == "g" else {
        return .Invalid("Missing type")
    }
    let thread: ThreadReference
    if lexer.expectAndConsume("-") {
        guard lexer.expectAndConsume("1") else {
            return .Invalid("Invalid thread number")
        }
        thread = .All
    } else {
        guard let threadID = lexer.expectAndConsumeHexBigEndianInteger() else {
            return .Invalid("Invalid thread number")
        }
        thread = threadID == 0 ? .Any : .ID(threadID)
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
private func handleCurrentThreadQuery(inout server: DebugServerState, payload: String) -> ParseResult {
    let threadID = server.currentThreadID
    // Set the current thread as well to override the .Any and .All states.
    server.currentThread = .ID(threadID)
    return .Response("QC\(String(threadID, radix: 16, uppercase: false))")
}

// vCont?
private func handleVContQuery(inout server: DebugServerState, payload: String) -> ParseResult {
    // Support 'c' (continue) and 's' (step)
    return .Response("vCont;c;s")
}

// c [addr]
private func handleContinue(inout server: DebugServerState, payload: String) -> ParseResult {
    var parser = PacketLexer(payload: payload, offset: 1)
    let address: COpaquePointer?
    if parser.hasContents {
        guard let addr = parser.expectAndConsumeHexBigEndianAddress() else {
            return .Invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    do {
        try server.debugger.resume(server.continueThread, action: .Continue, defaultAction: .Continue, address: address)
        // Don't send an OK as the response is the stopped/exited message.
        return .NoReply
    } catch {
        return .Error(.E25)
    }
}

// s [addr]
private func handleStep(inout server: DebugServerState, payload: String) -> ParseResult {
    var parser = PacketLexer(payload: payload, offset: 1)
    let address: COpaquePointer?
    if parser.hasContents {
        guard let addr = parser.expectAndConsumeHexBigEndianAddress() else {
            return .Invalid("Invalid address")
        }
        address = addr
    } else {
        address = nil
    }
    do {
        // Make all other threads stop when we are stepping.
        try server.debugger.resume(.ID(server.continueThreadID), action: .Step, defaultAction: .Stop, address: address)
        // Don't send an OK as the response is the stopped/exited message.
        return .NoReply
    } catch {
        return .Error(.E49)
    }
}

// z/Z packets control the breakpoints/watchpoints.
private func handleZ(inout server: DebugServerState, payload: String) -> ParseResult {
    var lexer = PacketLexer(payload: payload)
    guard let command = lexer.consumeCharacter(),
        breakpointType = lexer.consumeCharacter() else {
            return .Invalid("")
    }
    guard lexer.expectAndConsumeComma() else {
        return .Invalid("Missing comma separator")
    }
    guard let address = lexer.expectAndConsumeHexBigEndianAddress() else {
        return .Invalid("Invalid address")
    }
    guard lexer.expectAndConsumeComma() else {
        return .Invalid("Missing comma separator")
    }
    guard let byteSize = lexer.expectAndConsumeHexBigEndianInteger() else {
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

private func handleQShlibInfoAddr(inout server: DebugServerState, payload: String) -> ParseResult {
    do {
        let address = try server.debugger.getSharedLibraryInfoAddress()
        return .Response(address.bigEndianHexString)
    } catch {
        return .Error(.E44)
    }
}

private func handleQSymbol(inout server: DebugServerState, payload: String) -> ParseResult {
    // Don't need any symbol lookups.
    return .OK
}

private func handleQSupported(inout server: DebugServerState, payload: String) -> ParseResult {
    // Don't care about the payload here.
    return .Response("qXfer:features:read+;PacketSize=20000;qEcho+")
}

private func handleQXfer(inout server: DebugServerState, payload: String) -> ParseResult {
    // TODO: feature feature:read:target.xml
    // XML registers
    return .OK
}

// This will enabled thread suffix for the 'g', 'G', 'p', and 'P' commands.
private func handleQThreadSuffixSupported(inout server: DebugServerState, payload: String) -> ParseResult {
    server.threadSuffixSupported = true
    return .OK
}

// Returns host information.
private func handleQHostInfo(inout server: DebugServerState, payload: String) -> ParseResult {
    var result = ""
    if let (CPUType, CPUSubType) = getCPUType() {
        result.write("cputype:\(CPUType);cpusubtype:\(CPUSubType);")
    }
    #if os(OSX)
        result.write("ostype:macosx;watchpoint_exceptions_received:after;")
        result.write("vendor:apple;")
    #endif
    result.write("endian:little;") // FIXME: what about big?
    result.write("ptrsize:\(sizeof(COpaquePointer));")
    return .Response(result)
}

func getCPUType() -> (Int, Int)? {
    var type: UInt32 = 0
    var subtype: UInt32 = 0
    var err: Int32 = withUnsafeMutablePointer(&type) {
        var size = sizeofValue(type)
        return sysctlbyname("hw.cputype", $0, &size, nil, 0)
    }
    err |= withUnsafeMutablePointer(&subtype) {
        var size = sizeofValue(type)
        return sysctlbyname("hw.cpusubtype", $0, &size, nil, 0)
    }
    #if arch(x86_64) || arch(arm64)
        type |= UInt32(CPU_ARCH_ABI64)
    #endif
    return err == 0 ? (Int(type), Int(subtype)) : nil
}

private func handleQStartNoAckMode(inout server: DebugServerState, payload: String) -> ParseResult {
    // Send OK before changing the flag.
    // TODO: server.sendResponse(.OK)
    server.noAckMode = true
    return .NoReply
}

private func handleQEcho(inout server: DebugServerState, payload: String) -> ParseResult {
    // Send back the payload.
    return .Response(payload)
}

// vAttach
//, vAttachOrWait, vAttachName, vAttachWait
private func handleVAttach(inout server: DebugServerState, payload: String) -> ParseResult {
    // Do nothing
    // TODO:
    /// NotifyThatProcessStopped ();
    //return rnb_success;
    return .Unimplemented
}

// Implements a debug server that's partially compatible with the GDB remote protocol and supports a couple of LLDB extensions.
// GDB protocol reference:    [[TODO]]
// LLDB extensions reference: [[TODO]]
class DebugServer {
    private var state: DebugServerState
    private var handlers: [(String, (inout DebugServerState, String) -> ParseResult)]

    init(debugger: Debugger) {
        state = DebugServerState(debugger: debugger)
        handlers = []
        handlers = [
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
            ("H", handleSetCurrentThread),
            ("qC", handleCurrentThreadQuery),
            ("_M", handleAllocate),
            ("_m", handleDeallocate),
            ("qRegisterInfo", handleQRegisterInfo),
            ("qShlibInfoAddr", handleQShlibInfoAddr),
            ("qSymbol:", handleQSymbol),
            ("qSupported", handleQSupported),
            ("qHostInfo", handleQHostInfo),
            ("QThreadSuffixSupported", handleQThreadSuffixSupported),
            ("QStartNoAckMode", handleQStartNoAckMode),
            ("qEcho:", handleQEcho),
            ("k", handleK)
        ]
    }

    func handlePacketPayload(payload: String) -> ParseResult {
        for handler in handlers {
            if payload.hasPrefix(handler.0) {
                return handler.1(&state, payload)
            }
        }
        return .Unimplemented
    }

    func sendResponse(result: ParseResult) {
        func send(s: String) {
        }
        switch result {
        case .NoReply:
            break
        case .OK:
            send("OK")
        case .Response(let r):
            send(r)
        case .Unimplemented:
            send("")
        case .Invalid:
            send("E03")
        case .Error(let kind):
            send("\(kind)")
        }
    }
    
    private func sendPacket(payload: String) {
        guard !state.noAckMode else {
            // Output $\(string)#00
            print("$\(payload)#00")
            return
        }
        // Compute the hash.
        let hash = 0
        print("$\(payload)#TODO")
        // TODO:
    }
}

// If this packet is received, it allows us to send an extra key/value
// pair in the stop reply packets where we will list all of the thread IDs
// separated by commas:
//
//  "threads:10a,10b,10c;"
//
// This will get included in the stop reply packet as something like:
//
//  "T11thread:10a;00:00000000;01:00010203:threads:10a,10b,10c;"
//
// This can save two packets on each stop: qfThreadInfo/qsThreadInfo and
// speed things up a bit.
//
// Send the OK packet first so the correct checksum is appended...
func handleQListThreadsInStopReply() {
    //listThreadsInStopReply = true
}
