import SwiftUI

/// Building blocks of the approved visual language (design/visual-language.md,
/// decisions of October 19, 2026), shared by every page shown in the proposed
/// look on iPhone and Mac.
enum DuckLook {
  /// One card radius for cards and photo cards.
  static let cardRadius: CGFloat = 20
  /// Inner padding of a card; pages own the spacing between cards.
  static let cardPadding: CGFloat = 16
}

extension View {
  /// The one card style: grouped surface, 20 pt continuous radius, 16 pt padding.
  func duckLookCard() -> some View {
    padding(DuckLook.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckRole.groupedSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }
}

/// A secondary action inside a card: a tinted capsule, never link text.
struct DuckLookSecondaryButton: View {
  let title: LocalizedStringKey
  let action: () -> Void
  init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
  var body: some View {
    Button(action: action) { Text(title) }
      .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DuckRole.accent)
  }
}

/// A soft status pill with an optional colored dot ("• 34 not backed up").
struct DuckLookPill: View {
  let title: Text
  var dot: Color?
  var prominent = false
  var body: some View {
    HStack(spacing: prominent ? 8 : 6) {
      if let dot { Circle().fill(dot).frame(width: prominent ? 8 : 7, height: prominent ? 8 : 7) }
      title.font(prominent ? .subheadline.weight(.semibold) : .subheadline)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, prominent ? 14 : 12).padding(.vertical, prominent ? 8 : 6)
    .background(DuckRole.groupedSurface, in: Capsule())
  }
}
