/// The SPCC sensor a FITS `INSTRUME` names (card 0140).
///
/// The camera's model read in the instrument text, as Siril 1.4.4 lists its sensor (`SPCCNames`).
/// A suggestion only — the panel offers it, the user takes it (R2); an instrument the table does
/// not know gives none.
package struct SensorHint: Equatable, Sendable {
  /// The sensor as Siril spells it.
  package let sensor: String
  /// True when it is a name of the mono list (`-monosensor=`), else of the OSC one.
  package let mono: Bool

  /// A hint of `sensor`, mono or OSC.
  package init(sensor: String, mono: Bool) {
    self.sensor = sensor
    self.mono = mono
  }

  /// The hint for `instrume`, matched on a model token (spaces, dashes and case ignored) that no
  /// digit follows (« ASI2600MC » is not « ASI2600MC2 »).
  package static func suggest(instrume: String) -> Self? {
    let text = instrume.uppercased().filter { !" -_".contains($0) }
    return table.first { row in
      text.ranges(of: row.model).contains { range in
        text[range.upperBound...].first.map { !$0.isNumber } ?? true
      }
    }?.hint
  }

  private static let monoGroup = "Sony IMX411/455/461/533/571"

  /// Model token → hint: the cameras whose sensor Siril lists (no token holds another, so the
  /// first match is the only one).
  package static let table: [(model: String, hint: Self)] =
    osc.map { ($0, Self(sensor: $1, mono: false)) }
    + mono.map { ($0, Self(sensor: $1, mono: true)) }

  private static let osc = [
    ("ASI071MC", "Sony IMX071"), ("ASI178MC", "Sony IMX178"), ("ASI183MC", "Sony IMX183"),
    ("ASI224MC", "Sony IMX224"), ("ASI294MC", "Sony IMX294"), ("ASI385MC", "Sony IMX385"),
    ("ASI462MC", "Sony IMX462"), ("ASI482MC", "Sony IMX482"), ("ASI533MC", "Sony IMX533"),
    ("ASI585MC", "Sony IMX585"), ("ASI662MC", "Sony IMX662"), ("ASI676MC", "Sony IMX676"),
    ("ASI678MC", "Sony IMX678"), ("ASI715MC", "Sony IMX715"), ("ASI2400MC", "Sony IMX410"),
    ("ASI2600MC", "Sony IMX571"), ("ASI6200MC", "Sony IMX455"), ("QHY183C", "Sony IMX183"),
    ("QHY268C", "Sony IMX571"), ("QHY294C", "Sony IMX294"), ("QHY533C", "Sony IMX533"),
    ("QHY600C", "Sony IMX455"), ("QHY268PHC", "Sony IMX571"), ("QHY600PHC", "Sony IMX455"),
    ("QHY294PROC", "Sony IMX294"), ("POSEIDONC", "Sony IMX571"), ("ARESC", "Sony IMX533"),
    ("URANUSC", "Sony IMX585"), ("SEESTARS30", "ZWO Seestar S30"),
    ("SEESTARS50", "ZWO Seestar S50"),
  ]

  private static let mono = [
    ("ASI1600MM", "ZWO ASI1600MM"), ("ASI178MM", "Sony IMX178"), ("ASI183MM", "Sony IMX183"),
    ("ASI294MM", "Sony IMX492/294"), ("ASI533MM", monoGroup), ("ASI585MM", "Sony IMX585"),
    ("ASI2600MM", monoGroup), ("ASI6200MM", monoGroup), ("QHY183M", "Sony IMX183"),
    ("QHY268M", monoGroup), ("QHY294M", "Sony IMX492/294"), ("QHY533M", monoGroup),
    ("QHY600M", monoGroup), ("QHY268PHM", monoGroup), ("QHY600PHM", monoGroup),
    ("QHY294PROM", "Sony IMX492/294"), ("POSEIDONM", monoGroup), ("ARESM", monoGroup),
    ("URANUSM", "Sony IMX585"),
  ]
}
