import SwiftUI

/// Page sections keep their heading and content together. Adjacent sections
/// use sectionSpacing; actions cannot silently make one heading taller.
enum MacContentMetrics {
  static let sectionSpacing: CGFloat = 24
  static let headingContentSpacing: CGFloat = 12
  static let headingHeight: CGFloat = 32
}

struct MacContentSection<Content: View>: View {
  let title: LocalizedStringKey
  var actionTitle: LocalizedStringKey? = nil
  var actionIdentifier = ""
  var action: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: MacContentMetrics.headingContentSpacing) {
      HStack(spacing: 12) {
        Text(title).font(.system(size: 14, weight: .semibold))
        Spacer(minLength: 12)
        if let actionTitle, let action {
          Button(action: action) {
            HStack(spacing: 4) { Text(actionTitle); Image(systemName: "chevron.right").font(.system(size: 11)) }
          }.buttonStyle(.plain).foregroundStyle(DuckColors.action).font(.system(size: 14))
            .frame(minHeight: MacContentMetrics.headingHeight)
            .accessibilityIdentifier(actionIdentifier)
        }
      }.frame(minHeight: MacContentMetrics.headingHeight)
      content()
    }
  }
}
