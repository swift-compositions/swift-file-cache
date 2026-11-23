public import FIPS_180_4_Digest

extension File.Cache {
    /// What names an entry: a digest of whatever decides the bytes kept under it.
    public struct Key: Sendable, Hashable {
        public let digest: NIST.FIPS.`180`.`4`.Digest

        public init(digest: NIST.FIPS.`180`.`4`.Digest) {
            self.digest = digest
        }
    }
}

extension File.Cache.Key {
    /// The digest in lowercase hex, the name of the entry's file before `.entry`.
    public var hex: Swift.String { digest.hex }
}
