import SwiftUI

/// Shared components of the visual standard (design/visual-language.md) and the
/// interaction standard (design/interaction.md). Redesigned pages on iPhone and
/// Mac are built from these; they use tokens only.
enum DuckLook {
  #if os(macOS)
  /// V3: Mac cards use the compact radius and padding.
  static let cardRadius: CGFloat = DuckRadius.cardCompact
  static let cardPadding: CGFloat = DuckSpacing.small
  /// V4: on the Mac window background a card reads through a quiet system fill,
  /// as grouped settings do; `groupedSurface` matches the window there.
  static let cardSurface = Color(nsColor: .quaternarySystemFill)
  #else
  /// V3: one card radius for cards and photo cards.
  static let cardRadius: CGFloat = DuckRadius.card
  static let cardPadding: CGFloat = DuckSpacing.medium
  static let cardSurface = DuckRole.groupedSurface
  #endif
  /// V3: gap between photos in grids and mosaics.
  static let photoGap: CGFloat = 2
}

extension View {
  /// V3/V4: the one card style. Solid grouped surface, no border, no shadow.
  func duckCard() -> some View {
    padding(DuckLook.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
      .background(DuckLook.cardSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }

  /// I4: the one primary action of a context, a filled capsule.
  func duckPrimaryButton() -> some View {
    buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(DuckRole.accent)
  }
}

/// I4: an action inside a card, a tinted capsule; never link text.
struct DuckTintedButton: View {
  let title: LocalizedStringKey
  let action: () -> Void
  init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
  var body: some View {
    Button(action: action) { Text(title) }
      .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DuckRole.accent)
  }
}

/// A soft status pill with an optional colored dot ("• Pixel 8 Pro").
struct DuckPill: View {
  let title: Text
  var dot: Color?
  var body: some View {
    HStack(spacing: 6) {
      if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
      title.font(.footnote.weight(.semibold)).lineLimit(1)
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, DuckSpacing.small).padding(.vertical, 6)
    .background(DuckLook.cardSurface, in: Capsule())
    .accessibilityElement(children: .combine)
  }
}

/// I3: one card for every hub state and problem. A colored glyph, a neutral
/// title, the note, an optional progress overlay, an optional trailing control
/// and at most one action below. Its geometry stays stable while values change.
struct DuckStateCard<Trailing: View, Action: View>: View {
  let symbol: String
  let tone: Color
  let title: Text
  var note: Text?
  var progress: Double?
  @ViewBuilder var trailing: () -> Trailing
  @ViewBuilder var action: () -> Action

  init(symbol: String, tone: Color, title: Text, note: Text? = nil, progress: Double? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
    @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
    self.symbol = symbol; self.tone = tone; self.title = title; self.note = note; self.progress = progress
    self.trailing = trailing; self.action = action
  }

  var body: some View {
    HStack(alignment: .top, spacing: DuckSpacing.small) {
      Image(systemName: symbol).font(.title3).foregroundStyle(tone).frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        title.font(.headline).fixedSize(horizontal: false, vertical: true)
        if let note { note.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        if let progress {
          ProgressView(value: progress).tint(DuckRole.accent).padding(.top, 8)
            .animation(.easeOut(duration: DuckMotion.progress), value: progress)
        }
        action().padding(.top, 6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .duckCard()
    .accessibilityElement(children: .contain)
  }
}

/// I3: an empty state. The duck, one sentence, at most one action. Never used
/// for problems, missing access or failures (V6).
struct DuckEmptyState<Action: View>: View {
  let pose: DuckIllustration.Pose
  let title: LocalizedStringKey
  var note: LocalizedStringKey?
  @ViewBuilder var action: () -> Action

  init(pose: DuckIllustration.Pose, title: LocalizedStringKey, note: LocalizedStringKey? = nil,
    @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
    self.pose = pose; self.title = title; self.note = note; self.action = action
  }

  var body: some View {
    VStack(spacing: 10) {
      DuckIllustration(pose: pose, size: 112)
      Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
      if let note { Text(note).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
      action().padding(.top, 6)
    }
    .frame(maxWidth: .infinity).padding(.vertical, DuckSpacing.small)
    .duckCard()
  }
}

/// A section title with an optional trailing link ("Recently saved · See All").
struct DuckSectionHeader: View {
  let title: LocalizedStringKey
  var link: LocalizedStringKey?
  var action: (() -> Void)?
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(.footnote).foregroundStyle(.secondary)
      Spacer()
      if let link, let action {
        Button(action: action) { Text(link).font(.footnote) }.buttonStyle(.plain).foregroundStyle(DuckRole.accent)
      }
    }
    .padding(.horizontal, DuckSpacing.medium)
  }
}

/// P1/V3: the user's recently saved photos as evidence, inside one rounded
/// shape. Six or more: one large photo and five small; fewer: one row of
/// equal tiles, never an empty cell.
struct DuckPhotoMosaic: View {
  let sources: [String]
  var body: some View {
    Group {
      if sources.count >= 5 { mosaic } else { strip }
    }
    .clipShape(RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
    .accessibilityElement().accessibilityLabel(Text("hub_recent"))
  }

  private var strip: some View {
    GeometryReader { geometry in
      let count = CGFloat(max(min(sources.count, 4), 1))
      let side = (geometry.size.width - DuckLook.photoGap * (count - 1)) / count
      HStack(spacing: DuckLook.photoGap) {
        ForEach(sources.prefix(4), id: \.self) { AssetThumbnail(sourceID: $0, size: side, cornerRadius: 0) }
      }
    }
    .aspectRatio(CGFloat(max(min(sources.count, 4), 1)), contentMode: .fit)
  }

  /// One large photo (two by two) beside four small ones.
  private var mosaic: some View {
    GeometryReader { geometry in
      let gap = DuckLook.photoGap
      let small = (geometry.size.width - gap * 3) / 4
      let large = small * 2 + gap
      HStack(spacing: gap) {
        AssetThumbnail(sourceID: sources[0], size: large, cornerRadius: 0)
        VStack(spacing: gap) {
          HStack(spacing: gap) { tile(1, small); tile(2, small) }
          HStack(spacing: gap) { tile(3, small); tile(4, small) }
        }
      }
    }
    .aspectRatio(2, contentMode: .fit)
  }

  private func tile(_ index: Int, _ side: CGFloat) -> some View {
    AssetThumbnail(sourceID: sources[index], size: side, cornerRadius: 0)
  }
}
