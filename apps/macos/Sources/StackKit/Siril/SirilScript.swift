/// A Siril script: the fixed header, then one command per line, each ending in a newline.
package struct SirilScript: Equatable, Sendable {
  /// `scriptHeader` of the legacy engine.
  package static let header = "requires 1.2.0\nsetext fits\nset32bits\n"

  /// The commands after the header, in order.
  package var commands: [SirilCommand]

  /// A script of `commands`.
  package init(_ commands: [SirilCommand]) {
    self.commands = commands
  }

  /// The `.ssf` text, byte-identical to the legacy builders' output (with no CPU/memory limits).
  package func render() -> String {
    Self.header + commands.map { $0.line + "\n" }.joined()
  }
}
