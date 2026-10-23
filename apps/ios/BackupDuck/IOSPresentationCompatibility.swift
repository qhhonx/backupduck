import SwiftUI
import UIKit

extension View {
  /// iPad keeps a centered native form host. Modern SwiftUI allows fitting the
  /// horizontal size to the authored 540-point ideal; iOS 17 uses system form.
  @ViewBuilder func iosPrototypeSheetHost() -> some View {
    if UIDevice.current.userInterfaceIdiom == .pad {
      if #available(iOS 18.0, *) {
        self.frame(idealWidth: 540).presentationSizing(.form.fitted(horizontal: true, vertical: false))
      } else { self }
    } else { self }
  }
}
