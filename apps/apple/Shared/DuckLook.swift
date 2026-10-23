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
    #if os(iOS)
    buttonStyle(.borderedProminent).controlSize(.large).tint(DuckRole.accentFill)
    #else
    buttonStyle(.borderedProminent).controlSize(.regular).tint(DuckRole.accentFill).keyboardShortcut(.defaultAction)
    #endif
  }
}

/// I4: an action inside a card, a tinted capsule; never link text.
struct DuckTintedButton: View {
  let title: LocalizedStringKey
  let action: () -> Void
  init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
  var body: some View {
    Button(action: action) { Text(title) }
      .buttonStyle(.bordered).controlSize(.small).tint(DuckRole.accent)
  }
}

/// A soft status pill with an optional colored dot ("• Pixel 8 Pro").
struct DuckPill: View {
  let title: Text
  var dot: Color?
  var body: some View {
    HStack(spacing: 6) {
      if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
      title.font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(alignment: .top, spacing: DuckSpacing.small) {
      Image(systemName: symbol).font(.title3).foregroundStyle(tone).frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        title.font(.headline).fixedSize(horizontal: false, vertical: true)
        if let note { note.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        action().padding(.top, 6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .duckCard()
    .overlay(alignment: .bottom) {
      if let progress {
        ProgressView(value: progress).tint(DuckRole.accent)
          .animation(reduceMotion ? nil : .easeOut(duration: DuckMotion.progress), value: progress)
          .padding(.horizontal, DuckLook.cardPadding)
      }
    }
    .accessibilityElement(children: .contain)
  }
}

/// A10: empty and unavailable states sit at the optical center of their area:
/// the whole block's center at 45% of the height rather than 50%.
struct DuckOpticalCenter<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    GeometryReader { area in
      // Centering above a spacer of 10% of the height lifts the block by 5%,
      // whether the content fills the space it is offered or not.
      VStack(spacing: 0) {
        content
        Color.clear.frame(height: area.size.height * 0.1)
      }
      .frame(width: area.size.width, height: area.size.height)
    }
  }
}

extension View {
  /// A10: an empty or unavailable state that replaces a page's content.
  func duckOpticalCenter() -> some View {
    DuckOpticalCenter { self }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  /// The same inside a scrolling page: it fills the visible height.
  func duckFillsScrollHeight(reserving inset: CGFloat = 0) -> some View {
    DuckOpticalCenter { self }.frame(maxWidth: .infinity)
      .containerRelativeFrame(.vertical) { length, _ in max(0, length - inset) }
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
    ContentUnavailableView {
      if pose == .pairing {
        Label(title, systemImage: "iphone.and.arrow.forward")
      } else {
        DuckIllustration(pose: pose, size: 112)
        Text(title)
      }
    } description: {
      if let note { Text(note) }
    } actions: {
      action()
    }
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
  var frameChanged: ((String, CGRect) -> Void)? = nil
  var open: ((String, CGRect) -> Void)? = nil
  var body: some View {
    Group {
      if sources.count >= 5 { mosaic } else { strip }
    }
    .clipShape(RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
    .accessibilityElement(children: .contain).accessibilityLabel(Text("hub_recent"))
  }

  private var strip: some View {
    GeometryReader { geometry in
      let count = CGFloat(max(min(sources.count, 4), 1))
      let side = (geometry.size.width - DuckLook.photoGap * (count - 1)) / count
      HStack(spacing: DuckLook.photoGap) {
        ForEach(sources.prefix(4), id: \.self) { source in DuckMosaicPhoto(source: source, side: side, frameChanged: frameChanged, open: open) }
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
        DuckMosaicPhoto(source: sources[0], side: large, frameChanged: frameChanged, open: open)
        VStack(spacing: gap) {
          HStack(spacing: gap) { tile(1, small); tile(2, small) }
          HStack(spacing: gap) { tile(3, small); tile(4, small) }
        }
      }
    }
    .aspectRatio(2, contentMode: .fit)
  }

  private func tile(_ index: Int, _ side: CGFloat) -> some View {
    DuckMosaicPhoto(source: sources[index], side: side, frameChanged: frameChanged, open: open)
  }
}


private struct DuckMosaicPhoto: View {
  let source: String
  let side: CGFloat
  let frameChanged: ((String, CGRect) -> Void)?
  let open: ((String, CGRect) -> Void)?
  @State private var frame = CGRect.zero
  var body: some View {
    Group {
      if let open {
        Button { open(source, frame) } label: { thumbnail }.buttonStyle(.plain)
          .accessibilityLabel(Text("library_preview"))
          .accessibilityIdentifier("hub.recent.\(source)")
      } else { thumbnail }
    }
    .background(GeometryReader { proxy in
      Color.clear.onAppear { update(proxy.frame(in: .global)) }
        .onChange(of: proxy.frame(in: .global)) { _, value in update(value) }
    })
  }
  private var thumbnail: some View { AssetThumbnail(sourceID: source, size: side, cornerRadius: 0) }
  private func update(_ value: CGRect) { frame = value; frameChanged?(source, value) }
}

#if os(iOS)
/// A8: system appearance while browsing; immersive media uses the dark system canvas.
enum DuckViewerSurface {
  static let immersive = Color(uiColor: UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
}
#endif
