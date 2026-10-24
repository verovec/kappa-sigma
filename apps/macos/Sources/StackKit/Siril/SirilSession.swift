package import Foundation

/// A long-lived `siril-cli -p` session (design §4.4): commands on one FIFO, replies on another.
///
/// The protocol, checked on Siril 1.4.4: `ready` once; then per command `status: starting
/// <verb>`, `log:`/`progress:` lines, and `status: success|error <verb>`. Commands are queued and
/// run one at a time (an actor alone would interleave them across suspensions). A reply counts
/// only if it names the verb sent. If Siril dies during a command, a fresh instance is started and
/// the command fails with `SirilError.restarted`; if the caller's task is cancelled, Siril is
/// stopped (it is still busy with the command) and `CancellationError` is thrown.
package actor SirilSession {
  private let binary: String
  private let workDirectory: URL
  private let readyTimeout: Duration
  private var instance: SirilPipeInstance?
  private var busy = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  /// How many Siril processes this session started (1 + restarts).
  package private(set) var launches = 0
  /// The folder of the running Siril's FIFOs and owner marker; `nil` when none runs.
  package var fifoFolder: URL? { instance?.folder }

  /// A session over the `siril-cli` at `binary`, working in `workDirectory`; `start` fails if
  /// Siril does not say `ready` within `readyTimeout`.
  package init(binary: String, workDirectory: URL, readyTimeout: Duration = .seconds(60)) {
    self.binary = binary
    self.workDirectory = workDirectory
    self.readyTimeout = readyTimeout
  }

  /// Checks the install (≥ 1.4), starts Siril and waits for its `ready`.
  package func start() async throws {
    _ = try await SirilTool.verify(binary)
    stop()
    let fresh = try SirilPipeInstance(binary: binary, workDirectory: workDirectory)
    instance = fresh
    launches += 1
    let terminate = fresh.terminate
    let timeout = readyTimeout
    let watchdog = Task {
      do { try await Task.sleep(for: timeout) } catch { return false }
      terminate()
      return true
    }
    defer { watchdog.cancel() }
    while let line = await fresh.nextLine() {
      if line == "ready" { return }
    }
    try Task.checkCancellation()
    watchdog.cancel()
    let reason =
      await watchdog.value
      ? "no `ready` within \(GoFormat.shortest(Self.seconds(timeout))) seconds"
      : "siril-cli exited before it was ready"
    throw SirilError.sessionFailed(reason: reason)
  }

  /// Runs one command; returns its log lines (without `log:`), hands every line to `onLine`.
  package func exec(_ command: String, onLine: @Sendable (SirilLine) -> Void = { _ in })
    async throws -> [String]
  {
    await acquire()
    defer { release() }
    return try await perform(command, onLine: onLine)
  }

  /// Runs `commands` in order as one unit.
  ///
  /// No other caller's command runs in between (a script's
  /// `cd` must hold for its own commands). Returns the joined log lines.
  package func execScript(_ commands: [String], onLine: @Sendable (SirilLine) -> Void = { _ in })
    async throws -> [String]
  {
    await acquire()
    defer { release() }
    var log: [String] = []
    for command in commands { log += try await perform(command, onLine: onLine) }
    return log
  }

  /// One command, with the queue already held.
  private func perform(_ command: String, onLine: @Sendable (SirilLine) -> Void) async throws
    -> [String]
  {
    try Task.checkCancellation()
    if instance == nil { try await start() }
    guard let instance else { throw SirilError.sessionFailed(reason: "no instance") }
    let verb = String(command.split(separator: " ").first ?? "")
    try instance.send(command)
    var log: [String] = []
    while let raw = await instance.nextLine() {
      let line = SirilLine(parsing: raw)
      onLine(line)
      if let status = line.status, Self.statusVerb(raw) == verb {
        switch status {
        case .success: return log
        case .error: throw SirilError.commandFailed(command: verb, hint: Self.hint(log))
        case .starting, .exit: continue
        }
      } else if line.status == nil, raw.hasPrefix("log:") {
        log.append(line.text)
      }
    }
    if Task.isCancelled {
      stop()
      throw CancellationError()
    }
    // The reply stream ended: Siril died during the command.
    try await start()
    throw SirilError.restarted(command: verb)
  }

  /// Stops Siril (SIGTERM, then SIGKILL) and removes the pipes.
  package func stop() {
    instance?.terminate()
    instance = nil
  }

  // MARK: - Queue

  private func acquire() async {
    guard busy else {
      busy = true
      return
    }
    await withCheckedContinuation { waiting.append($0) }
  }

  /// Hands the session to the next waiting command, or frees it.
  private func release() {
    if waiting.isEmpty {
      busy = false
    } else {
      waiting.removeFirst().resume()
    }
  }

  // MARK: - Helpers

  /// The verb a `status: <word> <verb>` line names.
  private static func statusVerb(_ raw: String) -> String? {
    let words = raw.split(separator: " ")
    return words.count > 2 ? String(words[2]) : nil
  }

  /// The legacy keyword hint; Siril answers in the user's language, so a log matching none of
  /// the English keywords still reports its last line instead of nothing.
  private static func hint(_ log: [String]) -> String {
    let hint = SirilOutput.errorHint(log: log.map { "log: \($0)" }.joined(separator: "\n"))
    return hint.isEmpty ? (log.last ?? "") : hint
  }

  private static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
  }
}
