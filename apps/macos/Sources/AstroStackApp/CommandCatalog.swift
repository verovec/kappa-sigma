/// Every command of the app, in menu order (card 0079).
///
/// The menus and the shortcuts sheet are built from this list; a card adding a command (0069's
/// blink, keep/reject) declares it here with its stage. `CommandCatalogTests` fails on a shortcut
/// bound twice or a title missing in a language.
nonisolated package enum CommandCatalog {
  /// The commands, menu by menu, then those that live in a view.
  package static let commands: [AppCommand] =
    application + file + edit + view + window + help + viewer

  /// The command `id`, if declared.
  package static func command(_ id: String) -> AppCommand? {
    commands.first { $0.id == id }
  }

  /// The commands of `menu`, in order.
  package static func commands(in menu: CommandMenu) -> [AppCommand] {
    commands.filter { $0.menu == menu }
  }

  // MARK: - Menus

  private static let application: [AppCommand] = [
    AppCommand(
      "app.about", "About AstroStack", menu: .application,
      action: "orderFrontStandardAboutPanel:"),
    AppCommand(
      "app.settings", "Settings…", menu: .application, action: "showSettings:", key: ",",
      separatorBefore: true),
    AppCommand(
      "app.hide", "Hide AstroStack", menu: .application, action: "hide:", key: "h",
      separatorBefore: true),
    AppCommand(
      "app.hideOthers", "Hide Others", menu: .application, action: "hideOtherApplications:",
      key: "h", modifiers: [.command, .option]),
    AppCommand("app.showAll", "Show All", menu: .application, action: "unhideAllApplications:"),
    AppCommand(
      "app.quit", "Quit AstroStack", menu: .application, action: "terminate:", key: "q",
      separatorBefore: true),
  ]

  private static let file: [AppCommand] = [
    AppCommand("file.newProject", "New Project", menu: .file, action: "newDocument:", key: "n"),
    AppCommand("file.open", "Open…", menu: .file, action: "openDocument:", key: "o"),
    AppCommand("file.openImage", "Open Image…", menu: .file, action: "openImage:", key: "O"),
    AppCommand("file.openRun", "Open Run…", menu: .file, action: "openRun:", key: "r"),
    AppCommand(
      "file.close", "Close", menu: .file, action: "performClose:", key: "w",
      separatorBefore: true),
    AppCommand("file.save", "Save", menu: .file, action: "saveDocument:", key: "s"),
    AppCommand(
      "file.saveAs", "Save As…", menu: .file, action: "saveDocumentAs:", key: "s",
      modifiers: [.command, .shift]),
  ]

  private static let edit: [AppCommand] = [
    AppCommand("edit.undo", "Undo", menu: .edit, action: "undo:", key: "z"),
    AppCommand("edit.redo", "Redo", menu: .edit, action: "redo:", key: "Z"),
    AppCommand("edit.cut", "Cut", menu: .edit, action: "cut:", key: "x", separatorBefore: true),
    AppCommand("edit.copy", "Copy", menu: .edit, action: "copy:", key: "c"),
    AppCommand("edit.paste", "Paste", menu: .edit, action: "paste:", key: "v"),
    AppCommand("edit.selectAll", "Select All", menu: .edit, action: "selectAll:", key: "a"),
  ]

  private static let view: [AppCommand] = [
    AppCommand(
      "view.zoomToFit", "Zoom to Fit", menu: .view, action: "zoomToFit:", key: "0",
      stage: .studio),
    AppCommand(
      "view.actualPixels", "Actual Pixels", menu: .view, action: "zoomToActualSize:", key: "1",
      stage: .studio),
    // The Tri stage's blink and verdicts (card 0069): greyed unless a run waits at the review.
    AppCommand(
      "review.blinkPrevious", "Previous Frame", menu: .view, action: "blinkPrevious:",
      key: "\u{F702}", stage: .review, separatorBefore: true),
    AppCommand(
      "review.blinkNext", "Next Frame", menu: .view, action: "blinkNext:", key: "\u{F703}",
      stage: .review),
    AppCommand(
      "review.keep", "Keep Frame", menu: .view, action: "keepFrame:", key: "k", stage: .review),
    AppCommand(
      "review.reject", "Reject Frame", menu: .view, action: "rejectFrame:", key: "\u{8}",
      stage: .review),
    AppCommand(
      "review.continue", "Continue Stacking", menu: .view, action: "continueStacking:", key: "\r",
      stage: .review),
  ]

  private static let window: [AppCommand] = [
    AppCommand(
      "window.minimize", "Minimize", menu: .window, action: "performMiniaturize:", key: "m"),
    AppCommand("window.zoom", "Zoom", menu: .window, action: "performZoom:"),
    AppCommand(
      "window.bringAllToFront", "Bring All to Front", menu: .window, action: "arrangeInFront:",
      separatorBefore: true),
    AppCommand(
      "window.componentGallery", "Component Gallery", menu: .window,
      action: "showComponentGallery:", separatorBefore: true, debugOnly: true),
  ]

  private static let help: [AppCommand] = [
    AppCommand(
      // ⌘/, not ⌘?: macOS keeps ⌘? for the Help menu's search field.
      "help.shortcuts", "Keyboard Shortcuts", menu: .help, action: "showShortcuts:", key: "/"),
    AppCommand("help.glossary", "Glossary", menu: .help, action: "showGlossary:"),
    // A project window's guide (card 0061): greyed without a project window to answer it.
    AppCommand(
      "help.guide", "First-Stack Guide", menu: .help, action: "showGuide:", separatorBefore: true),
  ]

  /// Commands that live in a view, not a menu: keys held over the image.
  private static let viewer: [AppCommand] = [
    AppCommand(
      "viewer.compare", "Show the reference while held", menu: nil, action: nil,
      modifiers: .option, held: true, stage: .studio)
  ]
}
