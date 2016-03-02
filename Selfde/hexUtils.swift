//
//  hexUtils.swift
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
