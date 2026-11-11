package import Foundation

extension SirilRunner {
  /// A runner over one long-lived pipe session: each script becomes a `cd` to its folder, then
  /// its lines, one command at a time (the header's `requires`/`setext`/`set32bits` included).
  ///
  /// A script holding a command longer than the pipe reads (`SirilSession.maxCommandBytes`,
  /// card 0193) is handed whole to `fallback`, the script mode: the same commands in the same
  /// order, read from a file, which has no such limit. It still runs alone — the session's queue
  /// is held, so two Sirils never work at once — and says so on `onLine`.
  package static func pipe(_ session: SirilSession, fallback: Self) -> Self {
    Self(run: { script, directory, onLine in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let commands =
        ["cd \"\(directory.path)\""] + script.render().split(separator: "\n").map(String.init)
      if let long = commands.first(where: { !SirilSession.fits($0) }) {
        onLine(SirilLine(parsing: "log: " + Self.fallbackNote(long)))
        return try await session.alone { try await fallback.run(script, directory, onLine) }
      }
      // One unit: another script's `cd` must not land between this one's commands.
      let lines = try await session.execScript(commands, onLine: onLine)
      return lines.map { $0 + "\n" }.joined()
    })
  }

  /// The journal line of a script that left the pipe for script mode, naming the command.
  package static func fallbackNote(_ command: String) -> String {
    let verb = command.split(separator: " ").first.map(String.init) ?? ""
    return "\(verb): a command of \(command.utf8.count) bytes, more than Siril's pipe reads "
      + "(\(SirilSession.maxCommandBytes)) — this script runs in script mode"
  }

  /// The runner for `mode` over the `siril-cli` at `binary`; a pipe session works from `work`,
  /// and runs a script too long for the pipe in script mode.
  package static func make(mode: SirilMode, binary: String, work: URL) -> Self {
    switch mode {
    case .script: .live(binary: binary)
    case .pipe:
      .pipe(SirilSession(binary: binary, workDirectory: work), fallback: .live(binary: binary))
    }
  }
}
