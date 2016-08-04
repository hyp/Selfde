//
//  remoteDebuggingProtocol.swift
//  Selfde
//

extension Collection where Self.Iterator.Element == UInt8 {
    // Remote debugging protocol checksum.
    var checksum: UInt8 {
        var computedChecksum: UInt8 = 0
        for byte in self {
            computedChecksum = computedChecksum &+ byte // MOD 256.
        }
        return computedChecksum
    }
}

// Binary encoding that's used for x/X packets.
// Characters '}'  '#'  '$'  '*' are escaped with '}' (0x7d) character and then XOR'ed with 0x20.
extension Collection where Self.Iterator.Element == UInt8, Self.Index == Int, Self.IndexDistance == Int {
    var encodedBinaryData: [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity((count * 3) / 2) // Reserve 1.5 capacity to have enough space for escaped characters.
        for byte in self {
            switch byte {
            case UInt8(ascii: "#"), UInt8(ascii: "$"), UInt8(ascii: "}"), UInt8(ascii: "*"):
                output.append(UInt8(ascii: "}"))
                output.append(byte ^ 0x20)
            default:
                output.append(byte)
            }
        }
        return output
    }

    var decodedBinaryData: [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(Int(count))
        var i = startIndex
        let end = endIndex
        while i < end {
            switch self[i] {
            case UInt8(ascii: "}"):
                let nextIndex = (i + 1)
                guard nextIndex < end else {
                    output.append(UInt8(ascii: "}"))
                    i = nextIndex
                    break
                }
                output.append(self[nextIndex] ^ 0x20)
                i = i.advanced(by: 2)
            case let byte:
                output.append(byte)
                i = (i + 1)
            }
        }
        return output
    }
}

enum RemoteDebuggingPacket {
    case payload(String)
    case binaryPayload([UInt8])
    case ack
    case nack
    case interrupt
    case invalidChecksum
    case invalidPacket
}

func parsePackets(_ partialData: inout [UInt8], newData: ArraySlice<UInt8>, checkChecksums: Bool = true) -> [RemoteDebuggingPacket] {
    // Get the whole data.
    var dataBuffer = [UInt8]()
    let data: ArraySlice<UInt8>
    if partialData.isEmpty {
        data = newData
    } else {
        swap(&dataBuffer, &partialData) // Partial data becomes empty
        dataBuffer += newData
        data = dataBuffer[0..<dataBuffer.count]
    }
    // Extracts packets.
    var packets = [RemoteDebuggingPacket]()
    var i = data.startIndex
    let end = data.endIndex
    outerLoop: while i < end {
        switch data[i] {
        case UInt8(ascii: "+"):
            packets.append(.ack)
            i = (i + 1)
        case UInt8(ascii: "-"):
            packets.append(.nack)
            i = (i + 1)
        case UInt8(ascii: "$"):
            // Find '#'
            var j = (i + 1)
            while j < end {
                if data[j] == UInt8(ascii: "#") {
                    break
                }
                j = (j + 1)
            }
            guard (j + 3) <= end else {
                // No end found.
                break outerLoop
            }
            j = j.advanced(by: 3) // The '#' and checksum.
            packets.append(extractPayloadPacket(data[i..<j], checkChecksums: checkChecksums))
            i = j
        case 0x03:
            packets.append(.interrupt)
            i = (i + 1)
        default:
            // Junk byte, Ignore.
            i = (i + 1)
        }
    }

    // Store the partial data.
    if i < end {
        partialData = [UInt8](data[i..<end])
    }
    return packets
}

private func extractPayloadPacket(_ data: ArraySlice<UInt8>, checkChecksums: Bool = true) -> RemoteDebuggingPacket {
    assert(data.first == Optional(UInt8(ascii: "$")))
    let info = data.dropFirst(1)
    guard info.count >= 3 else {
        return .invalidPacket
    }
    let checksumInfo = info.suffix(3)
    let payload = info.dropLast(3)

    // Extract the sent checksum.
    if checkChecksums {
        assert(checksumInfo.count == 3)
        let checksumString = String(UnicodeScalar(checksumInfo[(checksumInfo.startIndex + 1)])) + String(UnicodeScalar(checksumInfo[checksumInfo.startIndex.advanced(by: 2)]))
        guard let checksum = Int(checksumString, radix: 16), checksumInfo[checksumInfo.startIndex] == UInt8(ascii: "#") else {
            return .invalidPacket
        }

        // Compute the checksum.
        if checksum != Int(payload.checksum) {
            return .invalidChecksum
        }
    }

    // Return the payload.
    if let first = payload.first, first == UInt8(ascii: "X") {
        // Binary writes need a binary payload.
        return .binaryPayload(Array(payload))
    }
    var str = ""
    str.reserveCapacity(payload.count)
    for byte in payload {
        str.write(String(UnicodeScalar(byte)))
    }
    return .payload(str)
}

// Parses the debugger packet payloads.
struct PacketParser {
    private let payload: String.UnicodeScalarView
    private var index: String.UnicodeScalarIndex
    private let endIndex: String.UnicodeScalarIndex

    init(payload: String, offset: Int = 0) {
        self.payload = payload.unicodeScalars
        index = self.payload.index(self.payload.startIndex, offsetBy: offset)
        endIndex = self.payload.endIndex
    }

    init(payload: String, offset: String.Index) {
        self.payload = payload.unicodeScalars
        index = offset.samePosition(in: self.payload)
        endIndex = self.payload.endIndex
    }

    var hasContents: Bool {
        return index < endIndex
    }

    mutating func consumeCharacter() -> UnicodeScalar? {
        guard index < endIndex else {
            return nil
        }
        let result = payload[index]
        index = payload.index(after: index)
        return result
    }

    mutating func consumeIfPresent(_ c: UnicodeScalar) -> Bool {
        guard index < endIndex && payload[index] == c else {
            return false
        }
        index = payload.index(after: index)
        return true
    }

    mutating func consumeComma() -> Bool {
        return consumeIfPresent(",")
    }

    private mutating func parseHexUInt64() -> (UInt64, Int) {
        var count = 0 // The number of hex characters.
        var result: UInt64 = 0
        while index < endIndex {
            guard let value = payload[index].hexValue else {
                break
            }
            result <<= 4
            result |= UInt64(value)
            count += 1
            index = payload.index(after: index)
        }
        return (result, count)
    }

    // Big endian unsigned 64 bit integer (most significant bytes come first).
    mutating func consumeHexUInt64() -> UInt64? {
        let (value, characterCount) = parseHexUInt64()
        guard characterCount != 0 && characterCount <= (sizeof(UInt64.self) * 2) else {
            // Empty string or too many hex digits.
            return nil
        }
        return value
    }

    // Big endian unsigned integer (most significant bytes come first).
    mutating func consumeHexUInt() -> UInt? {
        let (value, characterCount) = parseHexUInt64()
        guard characterCount != 0 && characterCount <= (sizeof(UInt.self) * 2) else {
            // Empty string or too many hex digits.
            return nil
        }
        // We can truncate here as we've made sure the number fits into the UInt.
        return UInt(truncatingBitPattern: value)
    }

    // Decimal unsigned integer.
    mutating func consumeUInt() -> UInt? {
        let startingIndex = index
        var result: UInt = 0
        while index < endIndex {
            let char = payload[index]
            guard case "0"..."9" = char else {
                break
            }
            var overflow: Bool
            (result, overflow) = UInt.multiplyWithOverflow(result, 10)
            (result, overflow) = overflow ? (result, overflow) : UInt.addWithOverflow(result, UInt(char.value - UnicodeScalar("0").value))
            guard !overflow else {
                return nil
            }
            index = payload.index(after: index)
        }
        return index != startingIndex ? result : nil
    }

    // Addresses are represented with big endian unsigned integers.
    mutating func consumeAddress() -> Address? {
        guard let address = consumeHexUInt() else {
            return nil
        }
        return Address(bitPattern: address)
    }

    private mutating func readHexBytes(upTo endIndex: String.UnicodeScalarView.Index) -> [UInt8]? {
        var result = [UInt8]()
        while payload.index(after: index) < endIndex {
            guard let high = payload[index].hexValue, let low = payload[payload.index(after: index)].hexValue else {
                break
            }
            // Not gonna overflow as high and low are both 15 max.
            result.append(UInt8(high &* 16 &+ low))
            index = payload.index(index, offsetBy: 2)
        }
        // Return nothing if there isn't an even number of hex digits, or when some character isn't a hex digit.
        return index < endIndex ? nil : result
    }

    mutating func readHexBytes() -> [UInt8]? {
        return readHexBytes(upTo: endIndex)
    }

    mutating func readHexBytes(size: Int) -> [UInt8]? {
        return readHexBytes(upTo: payload.index(index, offsetBy: size * 2))
    }
}
