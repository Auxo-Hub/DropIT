import Foundation

enum DER {
    static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ items: [Data]) -> Data {
        var body = Data()
        for item in items { body.append(item) }
        return tlv(0x30, body)
    }

    static func set(_ items: [Data]) -> Data {
        var body = Data()
        for item in items { body.append(item) }
        return tlv(0x31, body)
    }

    static func boolean(_ value: Bool) -> Data {
        return tlv(0x01, Data([value ? 0xFF : 0x00]))
    }

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var remaining = value
        if remaining == 0 {
            bytes = [0x00]
        } else {
            while remaining > 0 {
                bytes.insert(UInt8(remaining & 0xFF), at: 0)
                remaining >>= 8
            }
            if (bytes.first ?? 0) & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        }
        return tlv(0x02, Data(bytes))
    }

    static func octetString(_ data: Data) -> Data {
        return tlv(0x04, data)
    }

    static func bitString(_ data: Data, unusedBits: UInt8 = 0) -> Data {
        var body = Data([unusedBits])
        body.append(data)
        return tlv(0x03, body)
    }

    static func ia5String(_ value: String) -> Data {
        return tlv(0x16, Data(value.utf8))
    }

    static func printableString(_ value: String) -> Data {
        return tlv(0x13, Data(value.utf8))
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let text = formatter.string(from: date)
        return tlv(0x17, Data(text.utf8))
    }

    static func generalizedTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let text = formatter.string(from: date)
        return tlv(0x18, Data(text.utf8))
    }

    static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
        guard parts.count >= 2 else { return Data() }
        var body = Data([UInt8(parts[0] * 40 + parts[1])])
        for component in parts.dropFirst(2) {
            var chunk: [UInt8] = []
            var value = component
            repeat {
                chunk.insert(UInt8(value & 0x7F), at: 0)
                value >>= 7
            } while value > 0
            for i in 0..<(chunk.count - 1) {
                chunk[i] |= 0x80
            }
            body.append(contentsOf: chunk)
        }
        return tlv(0x06, body)
    }

    static func subjectAltName(dnsNames: [String], ipAddresses: [String]) -> Data {
        var entries: [Data] = []
        for name in dnsNames {
            entries.append(tlv(0x82, Data(name.utf8)))
        }
        for ip in ipAddresses {
            guard let bytes = ipv4Bytes(ip) else { continue }
            entries.append(tlv(0x87, bytes))
        }
        return sequence(entries)
    }

    static func basicConstraints(isCA: Bool, pathLen: Int) -> Data {
        var items: [Data] = []
        if isCA { items.append(boolean(true)) }
        if pathLen >= 0 { items.append(integer(pathLen)) }
        return sequence(items)
    }

    static func extendedKeyUsage(_ usages: [String]) -> Data {
        return sequence(usages.map { oid($0) })
    }

    static func keyUsage(_ flags: [UInt8]) -> Data {
        let value = flags.contains { $0 != 0 } ? flags : [0x00]
        return bitString(Data(value), unusedBits: 0)
    }

    static func ipv4Bytes(_ address: String) -> Data? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes = Data()
        for part in parts {
            guard let value = UInt8(part), value <= 255 else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    static func null() -> Data {
        return Data([0x05, 0x00])
    }

    static func algorithmIdentifier(_ dotted: String) -> Data {
        return sequence([oid(dotted), null()])
    }

    static func contextSpecific(_ number: UInt8, _ content: Data) -> Data {
        return tlv(0xA0 | number, content)
    }

    static func attributeTypeAndValue(oid dotted: String, value: String) -> Data {
        return sequence([oid(dotted), printableString(value)])
    }

    static func rdnSequence(_ attributes: [(String, String)]) -> Data {
        let rdns = attributes.map { set([attributeTypeAndValue(oid: $0.0, value: $0.1)]) }
        return sequence(rdns)
    }

    static func subjectPublicKeyInfo(pkcs1PublicKey: Data) -> Data {
        let algorithm = algorithmIdentifier("1.2.840.113549.1.1.1")
        let keyBits = bitString(pkcs1PublicKey, unusedBits: 0)
        return sequence([algorithm, keyBits])
    }

    static func x509Extension(oid dotted: String, critical: Bool, value: Data) -> Data {
        var items: [Data] = [oid(dotted)]
        if critical { items.append(boolean(true)) }
        items.append(octetString(value))
        return sequence(items)
    }

    static func time(_ date: Date) -> Data {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return year < 2050 ? utcTime(date) : generalizedTime(date)
    }

    static func parseTime(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyMMddHHmmss'Z'", "yyyyMMddHHmmss'Z'"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) { return parsed }
        }
        return nil
    }
}

struct DERNode {
    let tag: UInt8
    let content: Data
    let end: Int
}

enum DERReader {
    static func read(_ data: Data, at offset: Int) -> DERNode? {
        guard offset + 2 <= data.count else { return nil }
        let tag = data[data.startIndex + offset]
        var cursor = offset + 1
        let first = data[data.startIndex + cursor]
        cursor += 1
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4, cursor + byteCount <= data.count else { return nil }
            for i in 0..<byteCount {
                length = (length << 8) | Int(data[data.startIndex + cursor + i])
            }
            cursor += byteCount
        }
        guard length >= 0, cursor + length <= data.count else { return nil }
        let content = data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + length))
        return DERNode(tag: tag, content: content, end: cursor + length)
    }

    static func children(_ node: DERNode) -> [DERNode] {
        var result: [DERNode] = []
        var offset = 0
        while offset < node.content.count {
            guard let child = read(node.content, at: offset) else { break }
            result.append(child)
            offset = child.end
        }
        return result
    }

    static func certificateValidity(_ der: Data) -> (notBefore: Date, notAfter: Date)? {
        guard let certificate = read(der, at: 0),
              let tbs = children(certificate).first else { return nil }
        let tbsChildren = children(tbs)
        var index = 0
        if let first = tbsChildren.first, first.tag == 0xA0 { index = 1 }
        guard tbsChildren.count > index + 3 else { return nil }
        let times = children(tbsChildren[index + 3])
        guard times.count == 2,
              let notBefore = DER.parseTime(String(decoding: times[0].content, as: UTF8.self)),
              let notAfter = DER.parseTime(String(decoding: times[1].content, as: UTF8.self)) else { return nil }
        return (notBefore, notAfter)
    }
}
