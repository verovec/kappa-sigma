package import Foundation
package import ProjectKit
internal import RenderKit
package import SwiftUI

/// The welcome window's content, shown at launch instead of an untitled project.
///
/// Recent projects, a new project named after its target, Open…, and the host tools; never
/// modal (R3).
package struct WelcomeView: View {
  private let model: WelcomeModel
  private let actions: Actions
  /// The launch review of the retention policy (card 0114), when one ran.
  private let retention: RetentionReview?

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

  /// The welcome content over `model`, acting through `actions`; `retention` adds its sheet and
  /// notice.
  package init(model: WelcomeModel, actions: Actions, retention: RetentionReview? = nil) {
    self.model = model
    self.actions = actions
    self.retention = retention
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
      Text(.app("Welcome to AstroStack")).font(.largeTitle)
      HStack(spacing: DesignMetrics.spacingM) {
        // ⌘N and ⌘O stay the menu's: File › New Project raises this same sheet.
        Button(.app("New Project…")) { model.isNaming = true }
        Button(.app("Open…"), action: actions.choose)
      }
      if let retention { RetentionNotice(review: retention) }
      recentList
      ToolStrip(model: model)
    }
    .padding(DesignMetrics.spacingXL)
    .frame(minWidth: 520, alignment: .topLeading)
    .background(DesignColor.surface.color)
    .sheet(isPresented: Binding(get: { model.isNaming }, set: { model.isNaming = $0 })) {
      NewProjectSheet(model: model, actions: actions)
    }
    .sheet(isPresented: asking) {
      if let retention { RetentionSheet(review: retention) }
    }
  }

  /// The retention sheet is up while it has stacks to ask about; closing it decides nothing.
  private var asking: Binding<Bool> {
    Binding(
      get: { !(retention?.pending.isEmpty ?? true) },
      set: { if !$0 { retention?.postpone() } })
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

  /// A recent project's counts, or that it cannot be read.
  nonisolated package static func counts(_ summary: ProjectSummary?) -> LocalizedStringResource {
    guard let summary else { return .app("Cannot be read") }
    return .app("Sources: \(summary.sources) · Stacks: \(summary.stacks)")
  }
}
