//
//  hexUtils.swift
//  Selfde
//

extension UnicodeScalar {
    var hexValue: UInt32? {
        switch self {
        case "0"..."9":
            return value &- UnicodeScalar("0").value
        case "a"..."f":
            return value &- UnicodeScalar("a").value &+ UInt32(10)
        case "A"..."F":
            return value &- UnicodeScalar("A").value &+ UInt32(10)
        default:
            return nil
        }
    }
}

extension Address {
    var bigEndianHexString: String {
        return String(self.bitPattern, radix: 16, uppercase: false)
    }
}

private extension UInt8 {
    var hexChar: UnicodeScalar {
        if self < 10 {
            return UnicodeScalar(UnicodeScalar("0").value &+ UInt32(self))
        } else {
            assert(self < 16)
            return UnicodeScalar(UnicodeScalar("a").value &+ UInt32(self &- 10))
        }
    }
}

extension Collection where Self.Iterator.Element == UInt8, Self.Index == Int, Self.IndexDistance == Int {
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
