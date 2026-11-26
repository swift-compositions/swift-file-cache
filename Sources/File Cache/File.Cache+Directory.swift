public import Environment_Core
public import File_System

#if !os(WASI)
    import Environment
#endif

extension File.Cache {
    #if !os(WASI)
        /// The directory `name` names in the user's caches, as the process's environment gives them now.
        public static func directory(_ name: Swift.String) -> File.Directory? {
            Self.directory(name, in: .current())
        }
    #endif

    /// The directory `name` names in the user's caches as an environment gives them: under `$HOME/Library/Caches`
    /// on Apple platforms, and elsewhere under `$XDG_CACHE_HOME`, or `$HOME/.cache` where that is unset or empty.
    /// Nil where no home is known, a variable that is empty counting as unset, or where the path is not valid.
    public static func directory(_ name: Swift.String, in environment: Environment.Snapshot) -> File.Directory? {
        func given(_ key: Swift.String) -> Swift.String? {
            environment[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        #if canImport(Darwin)
            let base = given("HOME").map { $0 + "/Library/Caches" }
        #else
            let base = given("XDG_CACHE_HOME") ?? given("HOME").map { $0 + "/.cache" }
        #endif
        guard let base else { return nil }
        do throws(Path::Path.Error) {
            return try File.Directory(validating: base + "/" + name)
        } catch {
            return nil
        }
    }
}
