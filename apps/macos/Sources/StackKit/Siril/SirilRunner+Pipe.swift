package import Foundation

extension SirilRunner {
  /// A runner over one long-lived pipe session: each script becomes a `cd` to its folder, then
  /// its lines, one command at a time (the header's `requires`/`setext`/`set32bits` included).
  package static func pipe(_ session: SirilSession) -> Self {
    Self(run: { script, directory, onLine in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let commands =
        ["cd \"\(directory.path)\""] + script.render().split(separator: "\n").map(String.init)
      // One unit: another script's `cd` must not land between this one's commands.
      let lines = try await session.execScript(commands, onLine: onLine)
      return lines.map { $0 + "\n" }.joined()
    })
  }

  /// The runner for `mode` over the `siril-cli` at `binary`; a pipe session works from `work`.
  package static func make(mode: SirilMode, binary: String, work: URL) -> Self {
    switch mode {
    case .script: .live(binary: binary)
    case .pipe: .pipe(SirilSession(binary: binary, workDirectory: work))
    }
  }
}
