internal import Foundation
package import SwiftUI

/// Every shared component in every state, on one page.
///
/// The debug « Component Gallery » window and the light/dark × fr/en screenshots of
/// `ComponentGalleryTests` show it. It does not scroll itself, so a test measures its whole
/// height; the window wraps it in a scroll view.
package struct ComponentGallery: View {
  /// Every status, in order.
  package static let statuses = DesignStatus.allCases
  /// An untouched default, then a moved value.
  package static let parameters = [
    ParameterValue(default: 0.115, range: 0...1),
    ParameterValue(default: 0.95, range: 0...1, value: 0.8),
  ]
  /// A missing tool, one being looked for, one found.
  package static let installStates: [InstallCardModel.State] = [
    .missing, .checking,
    .found(URL(fileURLWithPath: "/Applications/Siril.app/Contents/MacOS/siril")),
  ]

  @State private var parameters = Self.parameters
  @State private var installs = Self.installStates.map { InstallCardModel(state: $0) { nil } }
  @Environment(\.locale) private var locale

  /// The gallery.
  package init() {}

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXL) {
      tokens
      measurements
      statuses
      parameterRows
      tools
      empty
    }
    .padding(DesignMetrics.spacingXL)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Sections

  private var tokens: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(
        .renderKit("Tokens"),
        detail: .renderKit("Light and dark values resolve with the window's appearance."))
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
        alignment: .leading, spacing: DesignMetrics.spacingS
      ) {
        ForEach(DesignColor.allCases, id: \.self) { token in
          HStack(spacing: DesignMetrics.spacingS) {
            RoundedRectangle(cornerRadius: DesignMetrics.radiusSmall)
              .fill(token.color)
              .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.radiusSmall)
                  .strokeBorder(DesignColor.textSecondary.color.opacity(0.4))
              )
              .frame(width: 28, height: 20)
            // The token's code name: the gallery is a developer tool.
            Text(verbatim: "\(token)").font(.caption.monospaced())
          }
        }
      }
    }
  }

  private var measurements: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(.renderKit("Measurements"))
      MetricValue(
        .renderKit("Sky background"),
        value: LocaleNumber.decimal(
          1432.5, locale: locale,
          maxFractionDigits: 1, grouping: true), unit: "ADU",
        delta: LocaleNumber.minus("-12"))
      MetricValue(
        .renderKit("Star size (FWHM)"),
        value: LocaleNumber.decimal(2.41, locale: locale, maxFractionDigits: 2), unit: "px",
        status: .ok)
      MetricValue(
        .renderKit("Noise"),
        value: LocaleNumber.decimal(0.001_18, locale: locale, maxFractionDigits: 5),
        status: .attention)
    }
  }

  private var statuses: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(.renderKit("Statuses"))
      HStack(spacing: DesignMetrics.spacingL) {
        ForEach(Self.statuses, id: \.self) { status in
          StatusBadge(status, Self.word(for: status))
        }
      }
    }
  }

  private var parameterRows: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      SectionHeader(.renderKit("Parameters"))
      ForEach(parameters.indices, id: \.self) { index in
        ParameterRow(
          index == 0 ? .renderKit("Hα blend") : .renderKit("Hα ceiling"),
          parameter: $parameters[index],
          why: .renderKit("How much of the Hα layer is added to the red channel."),
          format: { LocaleNumber.decimal($0, locale: locale, maxFractionDigits: 3) },
          parse: { Double($0.replacing(locale.decimalSeparator ?? ".", with: ".")) })
      }
    }
  }

  private var tools: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      SectionHeader(.renderKit("Host tools"))
      ForEach(installs.indices, id: \.self) { index in
        InstallCard(
          tool: ["GraXpert", "StarNet2", "Siril"][index], reason: Self.reasons[index],
          installURL: URL(fileURLWithPath: "/Applications"), model: installs[index])
      }
    }
  }

  private var empty: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      SectionHeader(.renderKit("Empty state"))
      EmptyState(
        .renderKit("No image"), message: .renderKit("Open an image to inspect it."),
        systemImage: "photo")
    }
  }

  // MARK: - Words

  private static let reasons: [LocalizedStringResource] = [
    .renderKit("GraXpert models and removes the sky background."),
    .renderKit("StarNet separates the stars from the nebula for the star layer."),
    .renderKit("Siril calibrates, registers and stacks the frames."),
  ]

  private static func word(for status: DesignStatus) -> LocalizedStringResource {
    switch status {
    case .ok: .renderKit("Ready")
    case .attention: .renderKit("Needs a look")
    case .error: .renderKit("Failed")
    case .unavailable: .renderKit("Not available")
    }
  }
}
