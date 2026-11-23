import File_System
#if !os(Windows)
    import ISO_9945_Kernel_Time
#endif

extension File.Cache {
    /// Marks an entry as just used, by setting its times to now, so that it is removed after those used before it.
    static func used(_ file: File) {
        #if !os(Windows)
            let now = ISO.`9945`.Kernel.Time.realtime()
            do throws(Kernel.File.Times.Error) {
                try Kernel.File.Times.set(access: now, modification: now, at: file.path.view)
            } catch {}
        #endif
    }

    /// Counts the bytes of the entries' files and, past the limit, removes entries from the least recently used
    /// (kept or read) on until they hold at most nine tenths of it; gives the bytes left. Other files in the
    /// directory are neither counted nor removed. An entry another process removes meanwhile is skipped.
    func trimmed(to limit: Int) -> Int {
        let entries: [File.Directory.Entry]
        do throws(File.Directory.Contents.Error) {
            entries = try File.Directory.Contents.list(at: directory)
        } catch {
            return 0
        }
        var files: [(path: File.Path, size: Int, used: Kernel.Time)] = []
        for entry in entries where Swift.String(entry.name)?.hasSuffix(".entry") == true {
            guard let path = entry.pathIfValid else { continue }
            do throws(Kernel.File.Stats.Error) {
                let info = try File.System.Stat.info(at: path)
                files.append((path, Int(info.size.underlying), info.modificationTime))
            } catch {
                continue
            }
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > limit else { return total }
        let goal = limit / 10 * 9
        for file in files.sorted(by: { $0.used < $1.used }) {
            guard total > goal else { break }
            do throws(File.System.Delete.Error) {
                try File(file.path).delete.ifExists()
                total -= file.size
            } catch {
                continue
            }
        }
        return total
    }
}
