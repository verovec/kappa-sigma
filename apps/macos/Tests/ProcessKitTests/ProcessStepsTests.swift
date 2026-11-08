import ProcessKit
import Testing

/// A process's declared arrow steps name its own number parameters (cards 0085, 0179): a step
/// or a whole-number id that names nothing, or a flag, would never reach a row.
@Suite("Process steps — declared steps and whole numbers name number parameters")
struct ProcessStepsTests {
  @Test("every declared step and whole-number id is a number parameter of its process")
  func testDeclaredStepsNameNumberParams() throws {
    let registry = try ProcessRegistry.standard()
    for type in registry.types {
      let numbers = Set(
        type.schema.specs.compactMap { spec -> String? in
          guard case .number = spec.kind else { return nil }
          return spec.id
        })
      for id in Set(type.steps.keys).union(type.wholeNumbers) {
        #expect(numbers.contains(id), "\(type.id).\(id)")
      }
      let both = Set(type.steps.keys).intersection(type.wholeNumbers)
      #expect(both.isEmpty, "\(type.id) declares \(both) twice: the whole number wins")
    }
  }

  @Test(
    "the parameters a process reads as whole numbers are declared so",
    arguments: [
      ("geometry", "cropLeft"), ("background-extraction", "samples"),
      ("background-extraction", "degree"), ("sky-desat", "coreGuardPx"), ("hdr", "openRadius"),
      ("emission-screens", "starRadius"), ("emission-screens", "smooth"),
    ])
  func testWholeNumbersDeclared(process: String, id: String) throws {
    let type = try #require(try ProcessRegistry.standard().type(id: process))
    #expect(type.wholeNumbers.contains(id))
  }
}
