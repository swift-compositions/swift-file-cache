import Byte
import FIPS_180_4
import File_System_Test_Support
import Testing
import Thread_Pool

@testable import File_Cache

@Suite struct `File.Cache Tests` {
    static let temporary = File.Directory.Temporary.Scope(prefix: "file-cache-tests")

    static func key(_ text: Swift.String) -> File.Cache.Key {
        File.Cache.Key(digest: NIST.FIPS.`180`.`4`.SHA256.digest(Array(text.utf8).map(Byte.init(bitPattern:))))
    }

    static let payload: [Byte] = (0..<100_000).map { Byte(bitPattern: UInt8(truncatingIfNeeded: $0 &* 7)) }

    /// The names in a directory.
    static func names(_ directory: File.Directory) throws -> Set<Swift.String> {
        Set(try File.Directory.Contents.list(at: directory).compactMap { Swift.String($0.name) })
    }

    @Test func `kept bytes are read back as they were, and keeping again replaces them`() throws {
        try Self.temporary { directory in
            let cache = File.Cache(directory)
            let key = Self.key("one")
            #expect(cache.bytes(for: key) == nil)
            try cache.keep(Self.payload, for: key)
            #expect(cache.bytes(for: key) == Self.payload)
            try cache.keep([], for: key)
            #expect(cache.bytes(for: key) == [])
        }
    }

    @Test func `a directory that does not exist is a miss, and is made with its parents when the first entry is kept`() throws {
        try Self.temporary { directory in
            let deep = File.Directory(directory.path / "a" / "b")
            let cache = File.Cache(deep)
            let key = Self.key("deep")
            #expect(cache.bytes(for: key) == nil)
            try cache.keep(Self.payload, for: key)
            #expect(cache.bytes(for: key) == Self.payload)
        }
    }

    @Test func `an entry is one file named by its key, holding the magic, the format, the digest, the length, the Adler-32 and the payload`() throws {
        try Self.temporary { directory in
            let cache = File.Cache(directory)
            let key = Self.key("layout")
            let payload: [Byte] = Array("Wikipedia".utf8).map(Byte.init(bitPattern:))
            try cache.keep(payload, for: key)
            #expect(try Self.names(directory) == [key.hex + ".entry"])
            let entry = try #require(cache.file(for: key)).read.bytes()
            #expect(File.Cache.header(key) == 64)
            #expect(entry.count == 64 + payload.count)
            #expect(entry[0..<8].map(\.bitPattern) == Array("FILECACH".utf8))
            #expect(File.Cache.number(entry, at: 8) == 1)
            #expect(Array(entry[16..<48]) == key.digest.bytes)
            #expect(File.Cache.number(entry, at: 48) == UInt64(payload.count))
            // RFC 1950's example: the Adler-32 of "Wikipedia".
            #expect(File.Cache.number(entry, at: 56) == 0x11E6_0398)
            #expect(Array(entry[64...]) == payload)
        }
    }

    @Test func `a key of a digest of another length keeps its whole digest`() throws {
        try Self.temporary { directory in
            let cache = File.Cache(directory)
            let key = File.Cache.Key(digest: NIST.FIPS.`180`.`4`.SHA1.digest(Self.payload))
            try cache.keep(Self.payload, for: key)
            #expect(cache.bytes(for: key) == Self.payload)
            #expect(File.Cache.header(key) == 52)
            #expect(try #require(cache.file(for: key)).read.bytes().count == 52 + Self.payload.count)
        }
    }

    @Test func `an entry cut short, damaged, of another magic or format, or of another key is a miss`() throws {
        try Self.temporary { directory in
            let cache = File.Cache(directory)
            let key = Self.key("one")
            try cache.keep(Self.payload, for: key)
            let file = try #require(cache.file(for: key))
            let whole = try file.read.bytes()

            func flipped(_ offset: Int) -> [Byte] {
                var damaged = whole
                damaged[offset] = Byte(bitPattern: damaged[offset].bitPattern ^ 1)
                return damaged
            }

            for broken in [
                Array(whole.dropLast(5)),
                Array(whole.prefix(63)),
                [],
                whole + [Byte(bitPattern: 0)],
                flipped(64 + 1000),
                flipped(0),
                flipped(8),
                flipped(20),
                flipped(48),
                flipped(56),
            ] {
                try file.write.atomic(broken.span)
                #expect(cache.bytes(for: key) == nil)
            }

            let other = Self.key("two")
            try #require(cache.file(for: other)).write.atomic(whole.span)
            #expect(cache.bytes(for: other) == nil)
        }
    }

    @Test func `a directory that cannot be made fails to keep with directory`() throws {
        try Self.temporary { directory in
            let blocker = try #require(File.Cache(directory).file(for: Self.key("blocker")))
            try blocker.write.atomic(Self.payload.span)
            let cache = File.Cache(File.Directory(blocker.path / "inner"))
            #expect {
                try cache.keep(Self.payload, for: Self.key("one"))
            } throws: { error in
                guard case .directory = error as? File.Cache.Error else { return false }
                return true
            }
            #expect(cache.bytes(for: Self.key("one")) == nil)
        }
    }

    @Test func `processes keeping one entry at once leave one whole entry and nothing else`() async throws {
        try await Self.temporary { directory in
            let cache = File.Cache(directory)
            let key = Self.key("one")
            try await withThrowingTaskGroup(of: Void.self) { group in
                [Self.payload, []].forEach { payload in
                    (1...4).forEach { _ in group.addTask { try cache.keep(payload, for: key) } }
                }
                try await group.waitForAll()
            }
            let read = cache.bytes(for: key)
            #expect(read == Self.payload || read == [])
            #expect(try Self.names(directory) == [key.hex + ".entry"])
        }
    }

    @Test func `past its limit a cache removes the least recently kept or read entries, down to nine tenths of it`() throws {
        try Self.temporary { directory in
            let entry = Self.payload.count + 64
            let cache = File.Cache(directory, limit: .bytes(entry * 7 / 2))
            let (a, b, c, d) = (Self.key("a"), Self.key("b"), Self.key("c"), Self.key("d"))
            for key in [a, b, c] { try cache.keep(Self.payload, for: key) }
            #expect(cache.bytes(for: a) == Self.payload)
            try cache.keep(Self.payload, for: d)
            #expect(try Self.names(directory) == Set([a, c, d].map { $0.hex + ".entry" }))
            #expect(cache.bytes(for: b) == nil)
            let unlimited = File.Cache(directory)
            for index in 0..<4 { try unlimited.keep(Self.payload, for: Self.key("more \(index)")) }
            #expect(try Self.names(directory).count == 7)
        }
    }

    @Test func `a cache that must leave more free than the disk has keeps nothing, and one that leaves nothing keeps all`() throws {
        try Self.temporary { directory in
            let greedy = File.Cache(directory, limit: .leaving(0))
            for index in 0..<3 { try greedy.keep(Self.payload, for: Self.key("kept \(index)")) }
            #expect(try Self.names(directory).count == 3)
            let modest = File.Cache(directory, limit: .leaving(.max))
            try modest.keep(Self.payload, for: Self.key("gone"))
            #expect(try Self.names(directory).isEmpty)
        }
    }

    @Test func `the forms on a thread pool keep and read back what the others do, and trim past the limit`() async throws {
        try await Self.temporary { directory in
            let pool = Kernel.Thread.Pool()
            defer { pool.shutdown() }
            let entry = Self.payload.count + 64
            let cache = File.Cache(File.Directory(directory.path / "deep"), limit: .bytes(entry * 7 / 2))
            let (a, b, c, d) = (Self.key("a"), Self.key("b"), Self.key("c"), Self.key("d"))
            #expect(await cache.bytes(for: a, on: pool) == nil)
            for key in [a, b, c] { try await cache.keep(Self.payload, for: key, on: pool) }
            #expect(cache.bytes(for: b) == Self.payload)
            #expect(await cache.bytes(for: a, on: pool) == Self.payload)
            try await cache.keep(Self.payload, for: d, on: pool)
            #expect(await cache.bytes(for: c, on: pool) == nil)
            #expect(try Self.names(File.Directory(directory.path / "deep")) == Set([a, b, d].map { $0.hex + ".entry" }))
        }
    }
}
