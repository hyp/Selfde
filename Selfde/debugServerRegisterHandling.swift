//
//  debugServerRegisterHandling.swift
//  Selfde
//
// Based on RNBRemote.cpp register info initialization and handling code.

private struct RegisterMapEntry {
    let debugServerRegisterNumber: Int
    let offset: Int
    let info: DNBRegisterInfo
    let valueRegisterNumbers: [Int]
    let invalidateRegisterNumbers: [Int]
}

private func getRegisterSets() -> [DNBRegisterSetInfo] {
    var result = [DNBRegisterSetInfo]()
    // FIXME: move to target specific file.
    #if arch(x86_64)
        var registerSetCount: nub_size_t = 0
        let registerSet = getRegisterSetInfoX86_64(&registerSetCount)
        assert(registerSet != nil)
        for set in UnsafeBufferPointer(start: registerSet, count: registerSetCount) {
            result.append(set)
        }
    #endif
    assert(!result.isEmpty)
    return result
}

private func getRegisterEntries(_ registerSets: [DNBRegisterSetInfo]) -> [RegisterMapEntry] {
    var registers = [RegisterMapEntry]()
    var nameToRegisterNumber = [String:Int]()
    var registerNumber = 0
    var registerDataOffset = 0

    for set in registerSets {
        if set.registers == nil {
            continue
        }
        for register in UnsafeBufferPointer(start: set.registers, count: set.num_registers) {
            let entry = RegisterMapEntry(debugServerRegisterNumber: registerNumber, offset: registerDataOffset, info: register, valueRegisterNumbers: [], invalidateRegisterNumbers: [])
            registerNumber += 1
            if register.value_regs == nil {
                registerDataOffset += Int(register.size)
            }
            guard let name = String(validatingUTF8: register.name) else {
                assertionFailure()
                continue
            }
            nameToRegisterNumber[name] = entry.debugServerRegisterNumber
            registers.append(entry)
        }
    }
    
    // Now we must find any registers whose values are in other registers and fix up
    // the offsets since we removed all gaps...
    return registers.map { entry in
        var offset = entry.offset
        var valueRegisterNumbers = [Int]()
        var invalidateRegisterNumbers = [Int]()

        if entry.info.value_regs != nil {
            var newOffset = Int.max
            var i = 0
            while entry.info.value_regs[i] != nil {
                guard let name = String(validatingUTF8: entry.info.value_regs[i]!),
                    number = nameToRegisterNumber[name] else {
                        assertionFailure()
                        break
                }
                valueRegisterNumbers.append(number)
                assert(number < registers.count)
                let registerOffset = registers[number].offset + Int(entry.info.offset)
                if newOffset > registerOffset {
                    newOffset = registerOffset
                }
                i += 1
            }
            
            if newOffset != Int.max {
                offset = newOffset
            } else {
                assertionFailure()
                offset = Int.max
            }
        }

        if entry.info.update_regs != nil {
            var i = 0
            while entry.info.update_regs[i] != nil {
                guard let name = String(validatingUTF8: entry.info.update_regs[i]!),
                    number = nameToRegisterNumber[name] else {
                        assertionFailure()
                        break
                }
                invalidateRegisterNumbers.append(number)
                i += 1
            }
        }
        return RegisterMapEntry(debugServerRegisterNumber: entry.debugServerRegisterNumber, offset: offset, info: entry.info, valueRegisterNumbers: valueRegisterNumbers, invalidateRegisterNumbers: invalidateRegisterNumbers)
    }
}

struct DebuggerRegisterState {
    private let registerSets: [DNBRegisterSetInfo]
    private let registers: [RegisterMapEntry]
    private var valueStorage: [UInt8]
    private var savedRegisters: [UInt: [UInt8]] = [:]
    private var saveRegisterID: UInt = 1

    init(debugger: Debugger) {
        registerSets = getRegisterSets()
        registers = getRegisterEntries(registerSets)
        valueStorage = [UInt8](repeating: 0, count: debugger.registerContextSize)
    }

    mutating func emitThreadStopInfoRegistersForThread(_ threadID: ThreadID, debugger: Debugger, dest: inout String) throws {
        for register in registers {
            // Only emit the GPR registers that aren't contained in other registers.
            // FIXME: Make this better.
            if register.info.set == 1 && register.info.value_regs == nil {
                assert(register.debugServerRegisterNumber <= Int(UInt8.max))
                let number = [UInt8(truncatingBitPattern: register.debugServerRegisterNumber)]
                let bytes = try debugger.getRegisterValueForThread(threadID, registerID: register.info.reg, registerSetID: register.info.set, dest: &valueStorage)
                dest += "\(number.hexString):\(bytes.hexString);"
            }
        }
    }
}

// qRegisterInfo can be used to query the register set.
func handleQRegisterInfo(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "qRegisterInfo".characters.count)
    guard let registerID = parser.consumeHexUInt().flatMap({ Int($0) }) else {
        return .invalid("Invalid register number")
    }
    guard registerID < server.registerState.registers.count else {
        // No more registers.
        return .error(.e45)
    }
    let register = server.registerState.registers[registerID]
    var response = ""
    if let name = String(validatingUTF8: register.info.name) {
        response += "name:\(name);"
    }
    if let alt = register.info.alt, altName = String(validatingUTF8: alt) {
        response += "alt-name:\(altName);"
    }

    response += "bitsize:\(register.info.size * 8);"
    response += "offset:\(register.offset);"

    switch DNBRegisterType(UInt32(register.info.type)) {
    case Uint:      response += "encoding:uint;"
    case Sint:      response += "encoding:sint;"
    case IEEE754:   response += "encoding:ieee754;"
    case Vector:    response += "encoding:vector;"
    default:
        assertionFailure()
    }

    switch DNBRegisterFormat(UInt32(register.info.format)) {
    case Binary:            response += "format:binary;"
    case Decimal:           response += "format:decimal;"
    case Hex:               response += "format:hex;"
    case Float:             response += "format:float;"
    case VectorOfSInt8:     response += "format:vector-sint8;"
    case VectorOfUInt8:     response += "format:vector-uint8;"
    case VectorOfSInt16:    response += "format:vector-sint16;"
    case VectorOfUInt16:    response += "format:vector-uint16;"
    case VectorOfSInt32:    response += "format:vector-sint32;"
    case VectorOfUInt32:    response += "format:vector-uint32;"
    case VectorOfFloat32:   response += "format:vector-float32;"
    case VectorOfUInt128:   response += "format:vector-uint128;"
    default:
        assertionFailure()
    }

    if Int(register.info.set) < server.registerState.registerSets.count {
        if let name = String(validatingUTF8: server.registerState.registerSets[Int(register.info.set)].name) {
            response += "set:\(name);"
        } else {
            assertionFailure()
        }
    }
    if register.info.reg_ehframe != INVALID_NUB_REGNUM {
        response += "ehframe:\(register.info.reg_ehframe);"
    }
    if register.info.reg_dwarf != INVALID_NUB_REGNUM {
        response += "dwarf:\(register.info.reg_dwarf);"
    }

    switch Int32(bitPattern: register.info.reg_generic) {
    case GENERIC_REGNUM_FP:     response += "generic:fp;"
    case GENERIC_REGNUM_PC:     response += "generic:pc;"
    case GENERIC_REGNUM_SP:     response += "generic:sp;"
    case GENERIC_REGNUM_RA:     response += "generic:ra;"
    case GENERIC_REGNUM_FLAGS:  response += "generic:flags;"
    case GENERIC_REGNUM_ARG1:   response += "generic:arg1;"
    case GENERIC_REGNUM_ARG2:   response += "generic:arg2;"
    case GENERIC_REGNUM_ARG3:   response += "generic:arg3;"
    case GENERIC_REGNUM_ARG4:   response += "generic:arg4;"
    case GENERIC_REGNUM_ARG5:   response += "generic:arg5;"
    case GENERIC_REGNUM_ARG6:   response += "generic:arg6;"
    case GENERIC_REGNUM_ARG7:   response += "generic:arg7;"
    case GENERIC_REGNUM_ARG8:   response += "generic:arg8;"
    default: break
    }

    if !register.valueRegisterNumbers.isEmpty {
        response += "container-regs:"
        for (i, registerNumber) in register.valueRegisterNumbers.enumerated() {
            if i > 0 { response += "," }
            response += String(registerNumber, radix: 16, uppercase: false)
        }
        response += ";"
    }

    if !register.invalidateRegisterNumbers.isEmpty {
        response += "invalidate-regs:"
        for (i, registerNumber) in register.invalidateRegisterNumbers.enumerated() {
            if i > 0 { response += "," }
            response += String(registerNumber, radix: 16, uppercase: false)
        }
        response += ";"
    }

    return .response(response)
}

// p register
func handleRegisterRead(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let registerID = parser.consumeHexUInt().flatMap({ Int($0) }) else {
        return .invalid("Invalid register number")
    }
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    guard registerID < server.registerState.registers.count else {
        server.logger?.log("Unknown register number requested: \(registerID)")
        return .error(.e47)
    }
    let register = server.registerState.registers[registerID]
    assert(register.info.reg != INVALID_NUB_REGNUM)
    assert(register.info.set != INVALID_NUB_REGNUM)
    do {
        let bytes = try server.debugger.getRegisterValueForThread(threadID, registerID: register.info.reg, registerSetID: register.info.set, dest: &server.registerState.valueStorage)
        assert(bytes.count == Int(register.info.size))
        return .response(bytes.hexString)
    } catch {
        // FIXME: Is this a good behaviour? (DebugServer tries to report really empty registers)
        return .error(.e32)
    }
}

// P register = value
func handleRegisterWrite(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let registerID = parser.consumeHexUInt().flatMap({ Int($0) }) else {
        return .invalid("Invalid register number")
    }
    guard parser.consumeIfPresent("=") else {
        return .invalid("Missing equals sign")
    }
    guard registerID < server.registerState.registers.count else {
        server.logger?.log("Unknown register number requested: \(registerID)")
        return .error(.e47)
    }
    let register = server.registerState.registers[registerID]
    assert(register.info.reg != INVALID_NUB_REGNUM)
    assert(register.info.set != INVALID_NUB_REGNUM)
    guard let value = parser.readHexBytes(Int(register.info.size)) else {
        return .invalid("Invalid register value")
    }
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    do {
        try server.debugger.setRegisterValueForThread(threadID, registerID: register.info.reg, registerSetID: register.info.set, source: value[0..<value.count])
        return .ok
    } catch {
        return .error(.e32)
    }
}

// g
func handleGPRegistersRead(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    do {
        let bytes = try server.debugger.getRegisterContextForThread(threadID, dest: &server.registerState.valueStorage)
        assert(bytes.count == server.debugger.registerContextSize)
        return .response(bytes.hexString)
    } catch {
        return .error(.e74)
    }
}

// G context-value
func handleGPRegistersWrite(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: 1)
    guard let value = parser.readHexBytes(server.debugger.registerContextSize) else {
        return .invalid("Invalid register context value")
    }
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    do {
        try server.debugger.setRegisterContextForThread(threadID, source: value[0..<value.count])
        return .ok
    } catch {
        return .error(.e55)
    }
}

// QSaveRegisterState
func handleQSaveRegisterState(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    do {
        var storage = [UInt8](repeating: 0, count: server.registerState.valueStorage.count)
        let bytes = try server.debugger.getRegisterContextForThread(threadID, dest: &storage)
        assert(storage.count == bytes.count)
        let saveID = server.registerState.saveRegisterID
        // Reset back to 1 on overflow.
        switch UInt.addWithOverflow(server.registerState.saveRegisterID, 1) {
        case (let newSaveID, false):
            server.registerState.saveRegisterID = newSaveID
        case (_, true):
            server.registerState.saveRegisterID = 1
        }
        server.registerState.savedRegisters[saveID] = storage
        return .response("\(saveID)")
    } catch {
        return .error(.e75)
    }
}

// QRestoreRegisterState save-id
func handleQRestoreRegisterState(_ server: inout DebugServerState, payload: String) -> ResponseResult {
    var parser = PacketParser(payload: payload, offset: "QRestoreRegisterState:".characters.count)
    guard let saveID = parser.consumeUInt() else {
        return .invalid("Invalid save ID")
    }
    guard let threadID = server.extractThreadID(payload) else {
        return .invalid("No thread specified")
    }
    do {
        guard let savedRegisters = server.registerState.savedRegisters.removeValue(forKey: saveID) else {
            return .error(.e77)
        }
        try server.debugger.setRegisterContextForThread(threadID, source: savedRegisters[0..<savedRegisters.count])
        return .ok
    } catch {
        return .error(.e77)
    }
}
