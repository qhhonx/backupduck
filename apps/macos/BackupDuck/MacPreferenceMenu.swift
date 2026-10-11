import AppKit
import SwiftUI

enum MacPreferenceValueLayout {
  static let fontSize: CGFloat = 14
  static let indicatorWidth: CGFloat = 16
  static let gap: CGFloat = 8
  static let trailingInset: CGFloat = indicatorWidth + gap
}

struct MacPreferenceValue: View {
  var value: String?
  var indicator: String? = "chevron.right"
  var width: CGFloat = 130
  var body: some View {
    HStack(alignment: .center, spacing: MacPreferenceValueLayout.gap) {
      Text(value ?? "").monospacedDigit().lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .trailing)
        .foregroundStyle(DuckColors.textSecondary)
      Image(systemName: indicator ?? "chevron.right").font(.system(size: 11))
        .frame(width: MacPreferenceValueLayout.indicatorWidth)
        .foregroundStyle(DuckColors.action).opacity(indicator == nil ? 0 : 1).accessibilityHidden(true)
    }.font(.system(size: MacPreferenceValueLayout.fontSize)).frame(width: width).frame(minHeight: DuckPreferenceMetrics.desktopControlHeight)
  }
}

/// A value-only native menu anchor. NSButton owns the title/image layout so
/// AppKit cannot move the custom chevron to the other side of a SwiftUI label.
struct MacPreferenceMenu<Value: Hashable>: NSViewRepresentable {
  let title: String
  @Binding var selection: Value
  let options: [Value]
  let label: (Value) -> String
  var enabled = true
  var identifier = ""

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton()
    button.cell = MacPreferenceButtonCell(textCell: "")
    button.target = context.coordinator
    button.action = #selector(Coordinator.openMenu(_:))
    button.isBordered = false
    button.setButtonType(.momentaryChange)
    button.alignment = .right
    button.imagePosition = .imageTrailing
    button.font = .monospacedDigitSystemFont(ofSize: MacPreferenceValueLayout.fontSize, weight: .regular)
    button.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    button.title = label(selection)
    button.isEnabled = enabled
    button.contentTintColor = NSColor(DuckColors.action)
    button.setAccessibilityLabel(title)
    button.setAccessibilityValue(label(selection))
    button.setAccessibilityIdentifier(identifier)
    button.setAccessibilityRole(.popUpButton)
  }
  final class Coordinator: NSObject {
    var parent: MacPreferenceMenu
    init(_ parent: MacPreferenceMenu) { self.parent = parent }
    @objc func openMenu(_ button: NSButton) {
      guard parent.enabled else { return }
      let menu = NSMenu(title: parent.title)
      for (index, value) in parent.options.enumerated() {
        let item = NSMenuItem(title: parent.label(value), action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = index
        item.state = value == parent.selection ? .on : .off
        menu.addItem(item)
      }
      button.menu = menu
      defer { button.menu = nil }
      menu.popUp(positioning: menu.items.first(where: { $0.state == .on }),
        at: NSPoint(x: button.bounds.minX, y: button.bounds.midY), in: button)
    }
    @objc func choose(_ item: NSMenuItem) {
      guard parent.enabled, let index = item.representedObject as? Int,
        parent.options.indices.contains(index) else { return }
      parent.selection = parent.options[index]
    }
  }
}

private final class MacPreferenceButtonCell: NSButtonCell {
  override func titleRect(forBounds rect: NSRect) -> NSRect {
    var result = super.titleRect(forBounds: rect)
    result.origin.x = rect.minX
    result.size.width = max(0, rect.width - MacPreferenceValueLayout.trailingInset)
    return result
  }
  override func imageRect(forBounds rect: NSRect) -> NSRect {
    let size = MacPreferenceValueLayout.indicatorWidth
    return NSRect(x: rect.maxX - size, y: rect.midY - size / 2, width: size, height: size)
  }
}
