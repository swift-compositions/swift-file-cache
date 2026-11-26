import Environment_Core
import File_Cache
import Testing

@Suite struct `File.Cache Directory Tests` {
    static func directory(_ values: [Swift.String: Swift.String]) -> File.Directory? {
        File.Cache.directory("Studio/Frames", in: Environment.Snapshot(values))
    }

    #if canImport(Darwin)
        @Test func `on Apple platforms a name is under the home's Library Caches, whatever XDG says`() throws {
            let expected = try File.Directory(validating: "/Users/a/Library/Caches/Studio/Frames")
            #expect(Self.directory(["HOME": "/Users/a"]) == expected)
            #expect(Self.directory(["HOME": "/Users/a", "XDG_CACHE_HOME": "/x"]) == expected)
        }
    #else
        @Test func `elsewhere a name is under XDG_CACHE_HOME, or the home's .cache where that is unset or empty`() throws {
            #expect(Self.directory(["HOME": "/home/a", "XDG_CACHE_HOME": "/x"]) == (try File.Directory(validating: "/x/Studio/Frames")))
            let home = try File.Directory(validating: "/home/a/.cache/Studio/Frames")
            #expect(Self.directory(["HOME": "/home/a", "XDG_CACHE_HOME": ""]) == home)
            #expect(Self.directory(["HOME": "/home/a"]) == home)
        }
    #endif

    @Test func `with no home, or an empty one, there is no directory`() {
        #expect(Self.directory([:]) == nil)
        #expect(Self.directory(["HOME": ""]) == nil)
    }
}
