package import Foundation
package import ProjectKit
internal import RenderKit
package import StackKit
package import SwiftUI

/// The welcome window's content, shown at launch instead of an untitled project.
///
/// Recent projects, a new project named after its target, Open…, and the host tools; never
/// modal (R3).
package struct WelcomeView: View {
  private let model: WelcomeModel
  private let hostTools: HostTools
  private let actions: Actions
  @State private var naming = false
  @State private var target = ""
  @State private var error: UserFacingError?

  /// What the buttons do: the window opens documents, tests record the calls.
  package struct Actions {
    /// Opens the project at the URL.
    package var open: (URL) -> Void
    /// Shows the Open panel.
    package var choose: () -> Void
    /// Creates a project named after the target and returns it.
    package var create: (String) throws -> URL

    /// Actions with these closures.
    package init(
      open: @escaping (URL) -> Void, choose: @escaping () -> Void,
      create: @escaping (String) throws -> URL
    ) {
      self.open = open
      self.choose = choose
      self.create = create
    }
  }

  /// The welcome content over `model`, acting through `actions`.
  package init(model: WelcomeModel, hostTools: HostTools, actions: Actions) {
    self.model = model
    self.hostTools = hostTools
    self.actions = actions
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
      Text(.app("Welcome to AstroStack")).font(.largeTitle)
      HStack(spacing: DesignMetrics.spacingM) {
        Button(.app("New Project…")) { naming = true }.keyboardShortcut("n")
        Button(.app("Open…"), action: actions.choose).keyboardShortcut("o")
      }
      recentList
      ToolStrip(model: model, hostTools: hostTools)
    }
    .padding(DesignMetrics.spacingXL)
    .frame(minWidth: 520, alignment: .topLeading)
    .background(DesignColor.surface.color)
    .sheet(isPresented: $naming) { newProjectSheet }
  }

  @ViewBuilder
  private var recentList: some View {
    SectionHeader(.app("Recent projects"))
    if model.recent.isEmpty {
      Text(.app("No recent project")).foregroundStyle(DesignColor.textSecondary.color)
    }
    ForEach(model.recent) { project in
      Button {
        actions.open(project.url)
      } label: {
        HStack {
          Text(verbatim: project.target).font(.headline)
          Spacer()
          Text(Self.counts(project.summary))
            .font(DesignMetrics.captionFont).foregroundStyle(DesignColor.textSecondary.color)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private var newProjectSheet: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      Text(.app("New Project…")).font(.headline)
      TextField(text: $target) { Text(.app("Target")) }
      Text(.app("Name it after the target: M 31, NGC 7000, IC 1848…"))
        .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      if let error { StatusBadge(.error, error.message) }
      HStack {
        Spacer()
        Button(.app("Cancel"), role: .cancel) { naming = false }.keyboardShortcut(.cancelAction)
        Button(.app("Create")) { create() }.keyboardShortcut(.defaultAction)
          .disabled(NewProject.fileName(target).isEmpty)
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(width: 380)
  }

  private func create() {
    do {
      let url = try actions.create(target)
      naming = false
      error = nil
      actions.open(url)
    } catch {
      self.error = UserFacingError(error)
    }
  }

  /// A recent project's counts, or that it cannot be read.
  nonisolated package static func counts(_ summary: ProjectSummary?) -> LocalizedStringResource {
    guard let summary else { return .app("Cannot be read") }
    return .app("Sources: \(summary.sources) · Stacks: \(summary.stacks)")
  }
}
