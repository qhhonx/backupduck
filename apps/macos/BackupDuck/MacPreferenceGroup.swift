import AppKit
import SwiftUI

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
