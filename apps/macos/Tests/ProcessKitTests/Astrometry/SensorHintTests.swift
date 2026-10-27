import ProcessKit
import Testing

/// Card 0140: the FITS `INSTRUME` card read as the sensor Siril's SPCC lists — a suggestion,
/// matched on the camera's model, never a guess for an unknown one.
@Suite("SensorHint: INSTRUME → the SPCC sensor Siril lists, OSC or mono")
struct SensorHintTests {
  @Test(
    "testSuggest: the model in the instrument name gives the sensor and its list",
    arguments: [
      ("ZWO ASI2600MC Air", SensorHint(sensor: "Sony IMX571", mono: false)),
      ("ZWO ASI2600MC Pro", SensorHint(sensor: "Sony IMX571", mono: false)),
      ("ZWO ASI1600MM Pro", SensorHint(sensor: "ZWO ASI1600MM", mono: true)),
      ("ZWO ASI2600MM Pro", SensorHint(sensor: "Sony IMX411/455/461/533/571", mono: true)),
      ("ZWO ASI294MC Pro", SensorHint(sensor: "Sony IMX294", mono: false)),
      ("QHY268C", SensorHint(sensor: "Sony IMX571", mono: false)),
      ("QHY600PH-M", SensorHint(sensor: "Sony IMX411/455/461/533/571", mono: true)),
      ("QHY294PRO-M", SensorHint(sensor: "Sony IMX492/294", mono: true)),
      ("Seestar S50", SensorHint(sensor: "ZWO Seestar S50", mono: false)),
      ("Canon EOS R6", nil),
      ("", nil),
    ])
  func testSuggest(instrume: String, expected: SensorHint?) {
    #expect(SensorHint.suggest(instrume: instrume) == expected)
  }

  @Test("every sensor of the table is a name of its Siril list")
  func testNamesAreListed() {
    for hint in SensorHint.table.map(\.hint) {
      let list = hint.mono ? SPCCNames.monoSensors : SPCCNames.sensors
      #expect(list.contains(hint.sensor), "\(hint.sensor)")
    }
  }

  @Test("no model token holds another: one instrument, one row")
  func testTokensAreDistinct() {
    let tokens = SensorHint.table.map(\.model)
    #expect(Set(tokens).count == tokens.count)
    for token in tokens {
      #expect(!tokens.contains { $0 != token && $0.contains(token) }, "\(token)")
    }
  }
}
