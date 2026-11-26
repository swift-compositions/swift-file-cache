public import File_System
public import Thread_Pool

extension File.Cache {
    /// Why bytes were not kept.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The directory could not be made.
        case directory(File.System.Create.Directory.Error)

        /// The entry could not be written.
        case write(File.System.Write.Atomic.Error)

        /// The thread pool did not take the work: shut down, full, timed out or cancelled.
        case pool(Kernel.Thread.Pool.Error)
    }
}
