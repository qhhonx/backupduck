import AppKit
import SwiftUI

/// A shared desktop group. Rows own their height; parent stacks add no row gaps.
struct MacPreferenceGroup<Content: View>: View {
  enum Layout { case rows, content }
  var title: LocalizedStringKey? = nil
  var note: LocalizedStringKey? = nil
  var layout: Layout = .rows
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      DuckSurface(contentInsets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) {
        VStack(alignment: .leading, spacing: 0) {
          if let title {
            Text(title).font(.system(size: 16, weight: .semibold))
              .padding(.top, 20).padding(.bottom, 8)
          }
          content()
            .padding(.bottom, layout == .content ? 20 : 0)
        }
      }
      if let note {
        Text(note).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
      }
    }
  }
}

struct MacPreferenceRow<Control: View>: View {
  let title: LocalizedStringKey
  var note: LocalizedStringKey? = nil
  var first = true
  @ViewBuilder var control: () -> Control
  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 14))
        if let note {
          Text(note).font(.system(size: 12)).foregroundStyle(DuckColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      control().font(.system(size: 14)).controlSize(.small)
    }.padding(.vertical, 10).frame(minHeight: DuckPreferenceMetrics.rowHeight)
      .contentShape(Rectangle())
      .overlay(alignment: .top) { if !first { Divider() } }
  }
}

/// Clear only automatic initial focus; subsequent Tab navigation is native.
struct MacSheetInitialFocus: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { FocusView() }
  func updateNSView(_ nsView: NSView, context: Context) {}
  private final class FocusView: NSView {
    private var applied = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window, !applied else { return }
      applied = true
      DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
    }
  }
}

/// Preserve AppKit's intrinsic drawing width before positioning in a wider
/// SwiftUI slot. Otherwise a segmented picker is centered inside that slot and
/// its visible right edge differs from neighboring controls.
extension View {
  func duckDesktopSegments(width: CGFloat? = nil) -> some View {
    self.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
      .fixedSize(horizontal: true, vertical: true)
      .frame(width: width, height: 32, alignment: .trailing)
  }
}
