import SwiftUI
import UIKit

extension View {
  /// iPad keeps a centered native form host fitted horizontally to the
  /// authored 540-point ideal.
  @ViewBuilder func iosPrototypeSheetHost() -> some View {
    if UIDevice.current.userInterfaceIdiom == .pad {
      self.frame(idealWidth: 540).presentationSizing(.form.fitted(horizontal: true, vertical: false))
    } else { self }
  }
}
