public import Byte
import FIPS_180_4_Digest
public import File_System
import RFC_1950

extension File {
    /// Bytes kept in a directory under keys, one file an entry, to be read back by a later run instead of being
    /// made again. It is a cache: an entry may be missing, cut short, damaged or replaced at any time, and each of
    /// those is a miss, never an error.
    public struct Cache: Sendable {
        /// Where the entries are kept; made when the first is kept.
        public let directory: File.Directory

        /// The most bytes the entries' files may hold together before the least recently used are removed, or nil
        /// to remove none.
        public let limit: Int?

        /// What this value and its copies know of the bytes the entries hold.
        let ledger: Ledger

        public init(_ directory: File.Directory, limit: Int? = nil) {
            self.directory = directory
            self.limit = limit
            self.ledger = Ledger()
        }
    }
}

extension File.Cache {
    /// The bytes kept under a key, or nil when there are none, or the entry is cut short, damaged or of another
    /// key.
    public func bytes(for key: Key) -> [Byte]? {
        guard let file = file(for: key) else { return nil }
        let payload: [Byte]?
        do throws(File.System.Read.Full.Error) {
            payload = Self.payload(try file.read.bytes(), key: key)
        } catch {
            return nil
        }
        if payload != nil { Self.used(file) }
        return payload
    }

    /// Keeps bytes under a key, replacing what was there: written whole under a temporary name, then renamed into
    /// place, without waiting for the disk.
    public func keep(_ bytes: [Byte], for key: Key) throws(Error) {
        guard let file = file(for: key) else { return }
        do throws(File.System.Create.Directory.Error) {
            try directory.create.recursive()
        } catch {
            throw .directory(error)
        }
        let entry = Self.entry(bytes, key: key)
        do throws(File.System.Write.Atomic.Error) {
            try file.write.atomic(entry.span, options: .init(durability: .none))
        } catch {
            throw .write(error)
        }
        if let limit { ledger.kept(entry.count, within: limit, in: self) }
    }

    /// The entry's file: its key in hex, then `.entry`.
    func file(for key: Key) -> File? {
        do throws(File.Path.Component.Error) {
            return directory[try File.Path.Component(key.hex + ".entry")]
        } catch {
            return nil
        }
    }
}

extension File.Cache {
    /// The entries' format, which every entry states after the magic: raised whenever the layout of an entry
    /// changes, so entries of an earlier format are simply missed.
    static let format: UInt64 = 1

    /// The start of every entry.
    static let magic: [Byte] = Array("FILECACH".utf8).map(Byte.init(bitPattern:))

    /// The bytes before the payload of an entry under a key: the magic, the format, the key's digest, the
    /// payload's length and its Adler-32; 64 for a SHA-256 key.
    static func header(_ key: Key) -> Int {
        8 + 8 + key.digest.bytes.count + 8 + 8
    }

    static func number(_ value: UInt64, into bytes: inout [Byte]) {
        (0..<8).forEach { index in
            bytes.append(Byte(bitPattern: UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))))
        }
    }

    static func number(_ bytes: [Byte], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        (0..<8).reversed().forEach { index in
            value = value << 8 | UInt64(bytes[offset + index].bitPattern)
        }
        return value
    }

    /// An entry: the header, then the payload.
    static func entry(_ payload: [Byte], key: Key) -> [Byte] {
        var entry: [Byte] = []
        entry.reserveCapacity(header(key) + payload.count)
        entry.append(contentsOf: magic)
        number(format, into: &entry)
        entry.append(contentsOf: key.digest.bytes)
        number(UInt64(payload.count), into: &entry)
        number(UInt64(IETF.RFC.`1950`.Adler32.checksum(payload)), into: &entry)
        entry.append(contentsOf: payload)
        return entry
    }

    /// The payload of an entry, or nil when it is not a whole entry of this key.
    static func payload(_ entry: [Byte], key: Key) -> [Byte]? {
        let digest = key.digest.bytes
        let header = header(key)
        guard entry.count >= header,
            Array(entry[0..<8]) == magic,
            number(entry, at: 8) == format,
            Array(entry[16..<(16 + digest.count)]) == digest,
            number(entry, at: 16 + digest.count) == UInt64(entry.count - header)
        else { return nil }
        let payload = Array(entry[header...])
        guard number(entry, at: 24 + digest.count) == UInt64(IETF.RFC.`1950`.Adler32.checksum(payload)) else { return nil }
        return payload
    }
}
