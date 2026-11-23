import Synchronization

extension File.Cache {
    /// The bytes the entries' files are known to hold together, shared by a cache and its copies: nil until the
    /// directory is first counted, then what was counted plus what was kept since.
    final class Ledger: Sendable {
        let held = Mutex<Int?>(nil)
    }
}

extension File.Cache.Ledger {
    /// Counts an entry just kept, and when the entries may hold more than the limit, or have not been counted,
    /// counts them and removes the least recently used until they hold at most nine tenths of it.
    func kept(_ count: Int, within limit: Int, in cache: File.Cache) {
        held.withLock { held in
            if let known = held, known + count <= limit {
                held = known + count
                return
            }
            held = cache.trimmed(to: limit)
        }
    }
}
