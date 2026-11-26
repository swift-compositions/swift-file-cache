@_exported public import File_System
import Lock

extension File.Cache {
    /// The bytes the entries' files are known to hold together, shared by a cache and its copies, and whether they
    /// are being counted.
    ///
    /// A lock owns the count because a cache is kept from synchronous code as well as from tasks, so no actor can
    /// own it; its body only reads and writes the count, never a file.
    final class Ledger: Sendable {
        struct Count {
            /// What was counted plus what was kept since; nil until the directory is first counted.
            var held: Int?
            /// Whether a keep is counting the directory and removing entries now.
            var trimming = false
            /// What was kept while the directory was being counted.
            var pending = 0
        }

        let count = Lock(Count())
    }
}

extension File.Cache.Ledger {
    /// Counts an entry just kept; true when the entries may hold more than the limit, or have not been counted, and
    /// nobody is counting them: the caller is then to count them and remove the least recently used, and to say
    /// what is left with `trimmed(_:)`.
    func kept(_ bytes: Int, within limit: Int) -> Bool {
        count.withLock { count in
            if count.trimming {
                count.pending += bytes
                return false
            }
            if let known = count.held, known + bytes <= limit {
                count.held = known + bytes
                return false
            }
            count.trimming = true
            count.pending = 0
            return true
        }
    }

    /// The bytes the entries hold after a count claimed by `kept(_:within:)`.
    func trimmed(_ left: Int) {
        count.withLock { count in
            count.held = left + count.pending
            count.trimming = false
            count.pending = 0
        }
    }
}
