/// One preprocessing knob: the `PreprocessSettings` value it reads and writes, its kind and
/// bounds, and the panel level it shows at (card 0070).
///
/// `id` is the legacy wire key (`internal/pipeline/params_patch.go`) when the legacy engine had
/// one. A recorded patch uses it, so it is never renamed once shipped.
package struct Knob: Sendable, Identifiable {
  /// Where the panel shows it: simple is always visible, advanced behind the disclosure.
  package enum Level: String, Sendable {
    case simple, advanced
  }

  /// What a value of the knob is.
  package enum Kind: Equatable, Sendable {
    /// A number in `bounds`; `integer` refuses a fraction.
    case number(bounds: ClosedRange<Double>, integer: Bool)
    case flag
    /// One of `options` (ids, not words: the app words them).
    case choice(options: [String])
  }

  package let id: String
  package let level: Level
  package let kind: Kind
  private let read: @Sendable (PreprocessSettings) -> KnobValue
  private let write: @Sendable (inout PreprocessSettings, KnobValue) -> Void

  /// The knob's value in `settings`.
  package func value(in settings: PreprocessSettings) -> KnobValue {
    read(settings)
  }

  /// `value` is of this knob's kind and within its bounds or options.
  package func accepts(_ value: KnobValue) -> Bool {
    switch (kind, value) {
    case (.number(let bounds, let integer), .number(let number)):
      bounds.contains(number) && (!integer || number.rounded() == number)
    case (.flag, .flag): true
    case (.choice(let options), .choice(let id)): options.contains(id)
    default: false
    }
  }

  /// `settings` with this knob set to `value`; refuses a value it does not accept.
  func apply(_ value: KnobValue, to settings: inout PreprocessSettings) throws(KnobError) {
    guard accepts(value) else { throw .invalid(id: id, value: value.description) }
    write(&settings, value)
  }

  // MARK: - Builders

  /// A number at `path`.
  static func number(
    _ id: String, _ level: Level, _ bounds: ClosedRange<Double>,
    _ path: WritableKeyPath<PreprocessSettings, Double> & Sendable
  ) -> Self {
    Self(
      id: id, level: level, kind: .number(bounds: bounds, integer: false),
      read: { .number($0[keyPath: path]) },
      write: { if case .number(let number) = $1 { $0[keyPath: path] = number } })
  }

  /// A whole number at `path`.
  static func integer(
    _ id: String, _ level: Level, _ bounds: ClosedRange<Double>,
    _ path: WritableKeyPath<PreprocessSettings, Int> & Sendable
  ) -> Self {
    Self(
      id: id, level: level, kind: .number(bounds: bounds, integer: true),
      read: { .number(Double($0[keyPath: path])) },
      write: { if case .number(let number) = $1 { $0[keyPath: path] = Int(number) } })
  }

  /// An on/off flag at `path`.
  static func flag(
    _ id: String, _ level: Level, _ path: WritableKeyPath<PreprocessSettings, Bool> & Sendable
  ) -> Self {
    Self(
      id: id, level: level, kind: .flag, read: { .flag($0[keyPath: path]) },
      write: { if case .flag(let flag) = $1 { $0[keyPath: path] = flag } })
  }

  /// One of `options`, read and written by id.
  static func choice(
    _ id: String, _ level: Level, _ options: [String],
    read: @escaping @Sendable (PreprocessSettings) -> String,
    write: @escaping @Sendable (inout PreprocessSettings, String) -> Void
  ) -> Self {
    Self(
      id: id, level: level, kind: .choice(options: options), read: { .choice(read($0)) },
      write: { if case .choice(let choice) = $1 { write(&$0, choice) } })
  }
}
