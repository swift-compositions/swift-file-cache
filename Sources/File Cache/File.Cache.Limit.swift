extension File.Cache {
    /// How much the entries may hold together before the least recently used are removed.
    public enum Limit: Sendable, Hashable {
        /// At most these bytes.
        case bytes(Int)

        /// As much as leaves at least these bytes free on the disk that holds the directory: what the entries
        /// hold plus what the disk has free, less these bytes, read again whenever an entry is kept. Where the disk's
        /// free space cannot be read, nothing is removed.
        case leaving(Int)
    }
}

extension File.Cache.Limit: ExpressibleByIntegerLiteral {
    public init(integerLiteral bytes: Int) {
        self = .bytes(bytes)
    }
}
