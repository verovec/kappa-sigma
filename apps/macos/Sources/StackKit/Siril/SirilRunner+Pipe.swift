package import Foundation

extension SirilRunner {
  /// A runner over one long-lived pipe session: each script becomes a `cd` to its folder, then
  /// its lines, one command at a time (the header's `requires`/`setext`/`set32bits` included).
  ///
  /// A script holding a command longer than the pipe reads (`SirilSession.maxCommandBytes`,
  /// card 0193) is handed whole to `fallback`, the script mode: the same commands in the same
  /// order, read from a file, which has no such limit. Without a fallback the session refuses
  /// the command (`SirilError.commandTooLong`).
  package static func pipe(_ session: SirilSession, fallback: Self? = nil) -> Self {
    Self(run: { script, directory, onLine in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let commands =
        ["cd \"\(directory.path)\""] + script.render().split(separator: "\n").map(String.init)
      if let fallback, !Self.fitsThePipe(commands) {
        return try await fallback.run(script, directory, onLine)
      }
      // One unit: another script's `cd` must not land between this one's commands.
      let lines = try await session.execScript(commands, onLine: onLine)
      return lines.map { $0 + "\n" }.joined()
    })
  }

  /// Whether every command of `commands` is one Siril reads whole from its pipe.
  package static func fitsThePipe(_ commands: [String]) -> Bool {
    commands.allSatisfy { $0.utf8.count <= SirilSession.maxCommandBytes }
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
