//
//  remoteDebuggingProtocol.swift
//  Selfde
//

extension UnicodeScalar {
    var hexValue: UInt32? {
        switch self {
        case "0"..."9":
            return self.value - UnicodeScalar("0").value
        case "a"..."f":
            return self.value - UnicodeScalar("a").value + 10
        case "A"..."F":
            return self.value - UnicodeScalar("A").value + 10
        default:
            return nil
        }
    }
}

extension COpaquePointer {
    var bigEndianHexString: String {
        return String(unsafeBitCast(self, UInt.self), radix: 16, uppercase: false)
    }
}

private extension UInt8 {
    var hexChar: UnicodeScalar {
        if self < 10 {
            return UnicodeScalar(UnicodeScalar("0").value + UInt32(self))
        } else {
            assert(self < 16)
            return UnicodeScalar(UnicodeScalar("a").value + UInt32(self - 10))
        }
    }
}

extension CollectionType where Self.Generator.Element == UInt8, Self.Index == Int {
    var hexString: String {
        var output = ""
        output.reserveCapacity(count * 2)
        for byte in self {
            output.append((byte / 16).hexChar)
            output.append((byte % 16).hexChar)
        }
        return output
    }
}

enum PacketPayloadResult {
    case None
    case Payload(String)
    case ACK
    case NACK
    case InvalidChecksum
    case InvalidPacket
}

extension CollectionType where Self.Generator.Element == UInt8 {
    // Remote debugging protocol checksum.
    var checksum: UInt8 {
        var computedChecksum: UInt8 = 0
        for byte in self {
            computedChecksum = computedChecksum &+ byte // MOD 256.
        }
        return computedChecksum
    }
}

func extractPackets(inout partialData: [UInt8], newData: ArraySlice<UInt8>) -> [ArraySlice<UInt8>] {
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
    var packets = [ArraySlice<UInt8>]()
    var i = data.startIndex
    let end = data.endIndex
    outerLoop: while i < end {
        switch data[i] {
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            // Control packet.
            packets.append(data[i...i])
            i = i.successor()
            continue
        case UInt8(ascii: "$"):
            // Find '#'
            var j = i.successor()
            while j < end {
                if data[j] == UInt8(ascii: "#") {
                    break
                }
                j = j.successor()
            }
            guard (j + 3) <= end else {
                // No end found.
                break outerLoop
            }
            j = j.advancedBy(3) // The '#' and checksum.
            packets.append(data[i..<j])
            i = j
            continue
        default:
            // TODO: log
            print("Junk byte \(data[i])")
            i = i.successor()
            continue
        }
    }

    // Store the partial data.
    if i < end {
        partialData = [UInt8](data[i..<end])
    }
    return packets
}

func parseRawPacket(data: ArraySlice<UInt8>, checkChecksums: Bool = true) -> PacketPayloadResult {
    guard let first = data.first else {
        // Empty packet, ignore.
        return .None
    }
    switch first {
    case UInt8(ascii: "$"):
        let info = data.dropFirst(1)
        guard info.count >= 3 else {
            return .InvalidPacket
        }
        let checksumInfo = info.suffix(3)
        let payload = info.dropLast(3)

        // Extract the sent checksum.
        if checkChecksums {
            assert(checksumInfo.count == 3)
            let checksumString = String(UnicodeScalar(checksumInfo[checksumInfo.startIndex.successor()])) + String(UnicodeScalar(checksumInfo[checksumInfo.startIndex.advancedBy(2)]))
            guard let checksum = Int(checksumString, radix: 16) where checksumInfo[checksumInfo.startIndex] == UInt8(ascii: "#") else {
                return .InvalidPacket
            }
            
            // Compute the checksum.
            if checksum != Int(payload.checksum) {
                return .InvalidChecksum
            }
        }

        // Return the payload.
        var str = ""
        str.reserveCapacity(payload.count)
        for byte in payload {
            str.write(String(UnicodeScalar(byte)))
        }
        return .Payload(str)
    case UInt8(ascii: "+"):
        return .ACK
    case UInt8(ascii: "-"):
        return .NACK
    default:
        return .InvalidPacket
    }
}

// Parses the debugger packet payloads.
struct PacketParser {
    private let payload: String.UnicodeScalarView
    private var index: String.UnicodeScalarIndex
    private let endIndex: String.UnicodeScalarIndex
    
    init(payload: String, offset: Int = 0) {
        self.payload = payload.unicodeScalars
        index = self.payload.startIndex.advancedBy(offset)
        endIndex = self.payload.endIndex
    }

    init(payload: String, offset: String.Index) {
        self.payload = payload.unicodeScalars
        index = offset.samePositionIn(self.payload)
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
        index = index.successor()
        return result
    }
    
    mutating func expectAndConsume(c: UnicodeScalar) -> Bool {
        guard index < endIndex && payload[index] == c else {
            return false
        }
        index = index.successor()
        return true
    }
    
    mutating func expectAndConsumeComma() -> Bool {
        return expectAndConsume(",")
    }
    
    // HEX
    // Bit endian integer (most significant bytes come first).
    mutating func expectAndConsumeHexBigEndianInteger() -> UInt? {
        var count = 0 // The number of hex characters.
        var result: UInt = 0
        while index < endIndex {
            guard let value = payload[index].hexValue else {
                break
            }
            result <<= 4
            result |= UInt(value)
            count += 1
            index = index.successor()
        }
        guard count != 0 && count <= (sizeof(UInt) * 2) else {
            // Empty string or too many hex digits.
            return nil
        }
        return result
    }

    mutating func expectAndConsumeHexBigEndianAddress() -> COpaquePointer? {
        guard let address = expectAndConsumeHexBigEndianInteger() else {
            return nil
        }
        return COpaquePointer(bitPattern: address)
    }

    private mutating func readHexBytes(endIndex: String.UnicodeScalarView.Index) -> [UInt8]? {
        var result = [UInt8]()
        while index.successor() < endIndex {
            guard let high = payload[index].hexValue, low = payload[index.successor()].hexValue else {
                break
            }
            // Not gonna overflow as high and low are both 15 max.
            result.append(UInt8(high &* 16 &+ low))
            index = index.advancedBy(2)
        }
        // Return nothing if there isn't an even number of hex digits, or when some character isn't a hex digit.
        return index < endIndex ? nil : result
    }

    mutating func readHexBytes() -> [UInt8]? {
        return readHexBytes(endIndex)
    }

    mutating func readHexBytes(size: Int) -> [UInt8]? {
        return readHexBytes(index.advancedBy(size * 2))
    }
}
