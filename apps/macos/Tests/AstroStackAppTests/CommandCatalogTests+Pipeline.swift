import AppKit
import AstroStackApp
import Testing

extension CommandCatalogTests {
  /// Card 0088: Run (⌥⌘R), Continue (⌥⌘↩) and Replay… live in the Edit menu, on the Studio stage.
  @Test("the pipeline commands: Run ⌥⌘R, Continue ⌥⌘↩, Replay… without a key, on the Studio")
  func testPipelineCommands() throws {
    let run = try #require(CommandCatalog.command("studio.runPipeline"))
    let resume = try #require(CommandCatalog.command("studio.continuePipeline"))
    let replay = try #require(CommandCatalog.command("studio.replayPipeline"))
    for command in [run, resume, replay] {
      #expect(command.menu == .edit && command.stage == .studio)
    }
    #expect(run.shortcut?.key == "r" && run.shortcut?.flags == [.command, .option])
    #expect(resume.shortcut?.key == "\r" && resume.shortcut?.flags == [.command, .option])
    #expect(replay.shortcut == nil)
  }
}
