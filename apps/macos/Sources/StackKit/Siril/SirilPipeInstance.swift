internal import Darwin
internal import Foundation
internal import Subprocess
internal import System

/// One `siril-cli -p -r <in> -w <out>` process and its two FIFOs, owned by a `SirilSession`.
///
/// Both FIFOs are opened read-write by us, so neither open blocks and Siril can open its ends in
/// any order. Replies are split into lines by the reply handle's readability handler and fed
/// to a stream that the process watcher finishes when Siril exits — that end of stream is how
/// a crash is seen (our own write end keeps the FIFO from ever reporting end-of-file).
final class SirilPipeInstance {
  /// Stops Siril and removes the FIFOs; safe to call more than once, from any thread.
  let terminate: @Sendable () -> Void
  private let commands: FileHandle
  private var lines: AsyncStream<String>.Iterator

  init(binary: String, workDirectory: URL) throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/siril-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    do {
      let input = folder.appendingPathComponent("command.in").path
      let output = folder.appendingPathComponent("command.out").path
      for path in [input, output] where mkfifo(path, 0o600) != 0 {
        throw SirilError.sessionFailed(reason: "mkfifo \(path): errno \(errno)")
      }
      let commands = try Self.openReadWrite(input)
      let replies = try Self.openReadWrite(output)
      let (stream, continuation) = AsyncStream<String>.makeStream()
      // readabilityHandler fires as soon as bytes arrive (FileHandle.bytes would buffer a FIFO
      // until end-of-file) and runs off the cooperative pool, so nothing blocks it.
      let splitter = LineSplitter()
      replies.readabilityHandler = { handle in
        for line in splitter.append(handle.availableData) { continuation.yield(line) }
      }
      let process = Self.launch(binary, input: input, output: output, in: workDirectory) {
        continuation.finish()
      }
      self.commands = commands
      self.lines = stream.makeAsyncIterator()
      // Called by the session and by deinit, possibly at once: the closes must happen exactly
      // once, or the second close of a descriptor number can hit one Subprocess reused meanwhile.
      let teardown = RunOnce {
        process.cancel()
        replies.readabilityHandler = nil
        try? commands.close()
        try? replies.close()
        try? FileManager.default.removeItem(at: folder)
      }
      self.terminate = { teardown.run() }
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  deinit { terminate() }

  /// The next reply line, or `nil` once Siril has exited (or the task was cancelled).
  func nextLine() async -> String? {
    await lines.next(isolation: #isolation)
  }

  /// Sends one command line.
  func send(_ command: String) throws {
    try commands.write(contentsOf: Data((command + "\n").utf8))
  }

  /// Runs Siril until it exits or the task is cancelled (SIGTERM, then SIGKILL after 2 s).
  private static func launch(
    _ binary: String, input: String, output: String, in workDirectory: URL,
    onExit: @escaping @Sendable () -> Void
  ) -> Task<Void, Never> {
    var options = PlatformOptions()
    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
    let arguments = Arguments(["-p", "-r", input, "-w", output, "-d", workDirectory.path])
    return Task {
      _ = try? await Subprocess.run(
        .path(FilePath(binary)), arguments: arguments, platformOptions: options,
        output: .discarded, error: .discarded)
      onExit()
    }
  }

  private static func openReadWrite(_ path: String) throws -> FileHandle {
    let descriptor = open(path, O_RDWR)
    guard descriptor >= 0 else {
      throw SirilError.sessionFailed(reason: "open \(path): errno \(errno)")
    }
    return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }
}
