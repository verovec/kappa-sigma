internal import Foundation
internal import RenderKit
package import SwiftUI

/// The « New Project… » sheet: the target the project is named after, then Create.
///
/// A fresh sheet each time it is raised, so no earlier name or error lingers.
package struct NewProjectSheet: View {
  private let model: WelcomeModel
  private let actions: WelcomeView.Actions
  @State private var target: String
  @State private var error: UserFacingError?

  /// The sheet over `model`, creating through `actions`; `target` and `error` preset it (tests).
  package init(
    model: WelcomeModel, actions: WelcomeView.Actions, target: String = "",
    error: UserFacingError? = nil
  ) {
    self.model = model
    self.actions = actions
    _target = State(initialValue: target)
    _error = State(initialValue: error)
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      Text(.app("New Project…")).font(.headline)
      TextField(text: $target) { Text(.app("Target")) }
      Text(.app("Name it after the target: M 31, NGC 7000, IC 1848…"))
        .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      if let error { StatusBadge(.error, error.message) }
      HStack {
        Spacer()
        Button(.app("Cancel"), role: .cancel) { model.isNaming = false }
          .keyboardShortcut(.cancelAction)
        Button(.app("Create")) { error = Self.submit(target, model: model, actions: actions) }
          .keyboardShortcut(.defaultAction)
          .disabled(NewProject.fileName(target).isEmpty)
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(width: 380)
  }

  /// Creates the project named after `target`, lowers the sheet and opens it; the error to show
  /// otherwise (the sheet stays up).
  package static func submit(_ target: String, model: WelcomeModel, actions: WelcomeView.Actions)
    -> UserFacingError?
  {
    do {
      let url = try actions.create(target)
      model.isNaming = false
      actions.open(url)
      return nil
    } catch {
      return UserFacingError(error)
    }
  }
}
