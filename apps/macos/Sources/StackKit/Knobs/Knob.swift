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
    /// On or off.
    case flag
    /// One of `options` (ids, not words: the app words them).
    case choice(options: [String])
  }

  /// Who reads the knob (card 0121): one lane's stacker alone, or the canvas every lane shares.
  package enum Scope: Equatable, Sendable {
    /// One lane's stacker reads it alone: a split run may set it per lane.
    case lane
    /// The shared canvas reads it: one value for every lane, for this reason.
    case run(Shared)
  }

  /// Why a run-wide knob cannot differ per lane: every lane lands on one canvas.
  package enum Shared: String, CaseIterable, Sendable {
    /// The registration reference defines the canvas every lane is registered onto.
    case registration
    /// The crops cut every lane to the same field.
    case framing
    /// Several nights are matched on one scale and one seam for every lane.
    case nights
    /// The combine and its sky model read every lane together.
    case combine
    /// The run's breakpoints, toggled once on the Tri stage, pause every lane alike.
    case breakpoints
  }

  /// The wire id, stable once shipped.
  package let id: String
  /// Where the panel shows it.
  package let level: Level
  /// Number, flag or choice, with its bounds or options.
  package let kind: Kind
  /// Per lane or for the whole run.
  package private(set) var scope = Scope.lane
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

  /// `value` may differ per lane (card 0121): a lane knob, and a value it accepts.
  package func acceptsLane(_ value: KnobValue) -> Bool {
    scope == .lane && accepts(value)
  }

  /// `settings` with this knob set to `value`; refuses a value it does not accept.
  func apply(_ value: KnobValue, to settings: inout PreprocessSettings) throws(KnobError) {
    guard accepts(value) else { throw .invalid(id: id, value: value.description) }
    write(&settings, value)
  }

  /// This knob read by the shared canvas, for `reason`.
  func shared(_ reason: Shared) -> Self {
    var knob = self
    knob.scope = .run(reason)
    return knob
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
