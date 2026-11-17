import SwiftUI

enum DuckSubscriptionPlan: String, CaseIterable, Identifiable {
  case monthly, annual

  var id: Self { self }
  var productID: String { "app.backupduck.pro." + rawValue }
  var title: LocalizedStringKey { self == .monthly ? "subscription_monthly_plan" : "subscription_annual_plan" }
  var priceFormat: String { self == .monthly ? "subscription_monthly_price" : "subscription_annual_price" }

  init?(productID: String) {
    guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
    self = plan
  }
}

/// Localized store product facts are supplied by the host; prices are never guessed.
struct DuckSubscriptionOfferPresentation {
  var monthlyPrice: String?
  var annualPrice: String?
  var annualMonthlyEquivalent: String?
  var annualSavings: String?
  var busy = false
  var pending = false
  var error: String?
  var restoration: DuckSubscriptionRestoreState = .idle
  func price(for plan: DuckSubscriptionPlan) -> String? {
    plan == .monthly ? monthlyPrice : annualPrice
  }
  var availablePlans: [DuckSubscriptionPlan] {
    let order: [DuckSubscriptionPlan] = annualSavings == nil ? [.monthly, .annual] : [.annual, .monthly]
    return order.filter { price(for: $0) != nil }
  }
  func availablePlan(preferred: DuckSubscriptionPlan?) -> DuckSubscriptionPlan? {
    if let preferred { return price(for: preferred) == nil ? nil : preferred }
    return availablePlans.first
  }
}

/// Optical metrics for this Pro composition only; the approved artwork is unchanged.
private enum DuckSubscriptionMetrics {
  static let compactPhoneHeight: CGFloat = 736
  static let headerArtwork: CGFloat = 64
  static let compactArtwork: CGFloat = 48
  static let artworkOpticalScale: CGFloat = 1.62
  static let symbolColumn: CGFloat = DuckSpacing.large
  static let contentWidth: CGFloat = DuckSheetMetrics.width
  static let sectionSpacing: CGFloat = DuckSpacing.medium
  #if os(macOS)
  static let pageMargin: CGFloat = DuckSpacing.large
  #else
  static let pageMargin: CGFloat = DuckSpacing.medium
  #endif
}

/// One host-owned set of executors; presenting these views never buys anything.
struct DuckSubscriptionActions {
  let subscribe: (DuckSubscriptionPlan) -> Void
  let reload: () -> Void
  let restore: () -> Void
  let privacy: () -> Void
  let terms: () -> Void
}

private struct DuckProIdentity: View {
  @Environment(\.dynamicTypeSize) private var textSize
  #if os(iOS)
  @Environment(\.verticalSizeClass) private var verticalSize
  #endif
  private var artworkSide: CGFloat {
    #if os(iOS)
    if textSize > .large || verticalSize == .compact || UIScreen.main.bounds.height <= DuckSubscriptionMetrics.compactPhoneHeight {
      return DuckSubscriptionMetrics.compactArtwork
    }
    #endif
    return DuckSubscriptionMetrics.headerArtwork
  }
  var body: some View {
    VStack(spacing: DuckSpacing.xSmall) {
      // The source has transparent composition margins. Crop only those margins,
      // preserving the approved duck, crown, original colors and aspect ratio.
      DuckIllustration(pose: .premium, size: artworkSide * DuckSubscriptionMetrics.artworkOpticalScale)
        .frame(width: artworkSide, height: artworkSide).clipped()
      Text("subscription_pro_title").font(.title2.bold())
      Text("subscription_plan_includes").font(.subheadline).foregroundStyle(DuckRole.secondaryText)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity).foregroundStyle(DuckRole.primaryText)
  }
}

/// Included capabilities share one symbol column, text edge and solid surface.
private struct DuckProBenefits: View {
  private var rows: [(String, String)] {
    var result = [
      ("live", "livephoto"),
      ("automatic", "arrow.triangle.2.circlepath"),
      ("background", "arrow.up.doc"),
      ("earlier", "photo.stack")
    ]
    #if os(macOS)
    result.append(("folders", "folder"))
    #endif
    return result
  }
  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        HStack(alignment: .top, spacing: DuckSpacing.small) {
          Image(systemName: row.1).font(.body.weight(.medium)).foregroundStyle(DuckRole.secondaryText)
            .frame(width: DuckSubscriptionMetrics.symbolColumn, alignment: .center).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
            Text(LocalizedStringKey("subscription_benefit_" + row.0)).font(.body.weight(.semibold))
              .foregroundStyle(DuckRole.primaryText)
            Text(LocalizedStringKey("subscription_benefit_" + row.0 + "_note"))
              .font(.subheadline).foregroundStyle(DuckRole.secondaryText)
          }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(DuckLook.cardPadding)
        if index < rows.count - 1 {
          Divider().padding(.leading, DuckLook.cardPadding + DuckSubscriptionMetrics.symbolColumn + DuckSpacing.small)
        }
      }
    }.background(DuckLook.cardSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius, style: .continuous))
  }
}

/// Contextual offers use the same content and product facts as the Settings page.
struct DuckSubscriptionOffer: View {
  let presentation: DuckSubscriptionOfferPresentation
  let actions: DuckSubscriptionActions
  let cancel: () -> Void
  @State private var preferredPlan: DuckSubscriptionPlan?
  var body: some View {
    DuckSheetLayout(title: "subscription_pro_short", busy: presentation.busy,
      desktopWidth: DuckSubscriptionMetrics.contentWidth, desktopFitsContent: true, closeOnly: true,
      bottomContent: AnyView(DuckProPlans(presentation: presentation, actions: actions, preferredPlan: $preferredPlan, includesPurchaseButton: phone)),
      cancel: cancel) {
      VStack(spacing: DuckSubscriptionMetrics.sectionSpacing) {
        DuckProIdentity()
        DuckProBenefits()
        DuckSubscriptionSecondaryActions(presentation: presentation, actions: actions)
      }
    } actions: {
      #if os(macOS)
      DuckSubscriptionPurchaseButton(presentation: presentation, actions: actions, preferredPlan: preferredPlan)
      #endif
    }
  }
  private var phone: Bool {
    #if os(iOS)
    true
    #else
    false
    #endif
  }
}

/// Deliberate Settings navigation; state, benefits and plan share one content axis.
struct DuckSubscriptionOverviewPage: View {
  let presentation: DuckSubscriptionOfferPresentation
  let actions: DuckSubscriptionActions
  var body: some View {
    DuckProPageContent(access: nil, offer: presentation, actions: actions, accessAction: {})
  }
}

struct DuckSubscriptionStatusPresentation {
  enum State: String { case notSubscribed, checking, welcome, active, renewalOff, expired, unavailable, pending, error }
  var state: State
  /// Current access facts, not the price of an optional new product offer.
  var date: String?
  var monthlyPrice: String?
  var message: String?
  var restoration: DuckSubscriptionRestoreState = .idle
  var title: LocalizedStringKey { LocalizedStringKey("subscription_state_" + state.rawValue) }
  var summary: LocalizedStringKey { LocalizedStringKey("subscription_summary_" + state.rawValue) }
  var entrySummary: LocalizedStringKey { state == .notSubscribed ? "subscription_entry_upgrade" : summary }
  var note: LocalizedStringKey { LocalizedStringKey("subscription_note_" + state.rawValue) }
  var isPaid: Bool { state == .active || state == .renewalOff }
  var maySubscribe: Bool { [.notSubscribed, .welcome, .expired].contains(state) }
  var action: LocalizedStringKey {
    switch state {
    case .active, .renewalOff: "subscription_manage"
    case .expired: "subscription_subscribe_continue"
    case .notSubscribed, .welcome: "subscription_subscribe"
    case .unavailable, .error: "subscription_retry"
    case .checking, .pending: "subscription_check_status"
    }
  }
  var dateLabel: LocalizedStringKey {
    switch state {
    case .expired: "subscription_access_ended"
    case .renewalOff: "subscription_access_until"
    case .welcome: "subscription_welcome_until"
    default: "subscription_renews_on"
    }
  }
}

/// Every access state has one stable settings label and native icon treatment.
struct DuckProSettingsLabel: View {
  var body: some View {
    DuckSettingsLabel(title: "subscription_pro_title", symbol: "crown.fill", color: DuckGlyph.blue)
  }
}

struct DuckSubscriptionSettingsRow: View {
  let presentation: DuckSubscriptionStatusPresentation
  let open: () -> Void
  var body: some View {
    Button(action: open) {
      HStack(spacing: DuckSpacing.small) {
        DuckProSettingsLabel().foregroundStyle(DuckRole.primaryText)
        Spacer(minLength: DuckSpacing.small)
        Text(presentation.entrySummary).foregroundStyle(DuckRole.secondaryText)
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
          .foregroundStyle(DuckRole.secondaryText).accessibilityHidden(true)
      }.padding(.vertical, DuckSpacing.xSmall)
        .frame(minHeight: DuckPreferenceMetrics.rowHeight).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("subscription.settings.entry")
    #if os(iOS)
    .listRowInsets(EdgeInsets(top: 0, leading: DuckSpacing.medium, bottom: 0, trailing: DuckSpacing.medium))
    #endif
  }
}

/// New product offers are injected separately from current subscription facts.
struct DuckSubscriptionStatusPage: View {
  let presentation: DuckSubscriptionStatusPresentation
  var offer: DuckSubscriptionOfferPresentation? = nil
  var purchaseActions: DuckSubscriptionActions? = nil
  let action: () -> Void
  let restore: () -> Void
  var body: some View {
    DuckProPageContent(access: presentation, offer: offer, actions: purchaseActions, accessAction: action, restore: restore)
  }
}

private struct DuckProPageContent: View {
  let access: DuckSubscriptionStatusPresentation?
  let offer: DuckSubscriptionOfferPresentation?
  let actions: DuckSubscriptionActions?
  let accessAction: () -> Void
  var restore: (() -> Void)? = nil
  @State private var preferredPlan: DuckSubscriptionPlan?
  var body: some View {
    Group {
      #if os(macOS)
      // Bound the scroll region independently of its content's ideal height.
      VStack(spacing: 0) {
        scrollingContent.frame(minHeight: 0, maxHeight: .infinity)
        purchaseFooter
      }.frame(minHeight: 0, maxHeight: .infinity)
      #else
      scrollingContent.safeAreaInset(edge: .bottom, spacing: 0) { purchaseFooter }
      #endif
    }.background(DuckRole.background).navigationTitle("subscription_pro_short")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
  private var scrollingContent: some View {
    ScrollView {
      VStack(spacing: DuckSubscriptionMetrics.sectionSpacing) {
        DuckProIdentity()
        if let access {
          DuckProAccessGroup(presentation: access, action: accessAction)
        }
        DuckProBenefits()
        if let offer, let actions, access?.maySubscribe ?? true {
          DuckSubscriptionSecondaryActions(presentation: offer, actions: actions)
        } else if let actions {
          DuckSubscriptionSecondaryActions(presentation: .init(monthlyPrice: nil, restoration: access?.restoration ?? .idle), actions: actions)
        } else if let restore {
          DuckSubscriptionRestoreControl(state: access?.restoration ?? .idle, restore: restore)
          DuckSubscriptionRestoreFeedback(state: access?.restoration ?? .idle)
        }
      }
      .padding(DuckSubscriptionMetrics.pageMargin)
      .frame(maxWidth: DuckSubscriptionMetrics.contentWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
  }
  @ViewBuilder private var purchaseFooter: some View {
      if let offer, let actions, access?.maySubscribe ?? true {
        DuckProPlans(presentation: offer, actions: actions, preferredPlan: $preferredPlan,
          actionTitle: access?.state == .expired ? "subscription_subscribe_continue" : nil)
          .padding(.horizontal, DuckSubscriptionMetrics.pageMargin)
          .frame(maxWidth: DuckSubscriptionMetrics.contentWidth)
          .frame(maxWidth: .infinity)
          .background(DuckRole.background)
          .overlay(alignment: .top) { Divider() }
      }
  }

}

private struct DuckProAccessGroup: View {
  let presentation: DuckSubscriptionStatusPresentation
  let action: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.small) {
      HStack(spacing: DuckSpacing.xSmall) {
        if presentation.state == .checking { ProgressView().controlSize(.small) }
        Text(presentation.title).font(.headline).foregroundStyle(DuckRole.primaryText)
      }
      if presentation.state == .expired {
        Text("subscription_expired_continuity")
          .font(.subheadline).foregroundStyle(DuckRole.secondaryText)
      } else if presentation.state != .active {
        Text(presentation.note).font(.subheadline).foregroundStyle(DuckRole.secondaryText)
      }
      if let date = presentation.date { fact(presentation.dateLabel, value: date) }
      if let price = presentation.monthlyPrice { fact("subscription_monthly_plan", value: price) }
      if let message = presentation.message {
        DuckNotice(title: LocalizedStringKey(message), tone: .failure, symbol: "exclamationmark.circle")
      }
      if !presentation.maySubscribe {
        HStack {
          #if os(macOS)
          Spacer(minLength: 0)
          #endif
          Button(presentation.action, action: action).duckPrimaryButton().accessibilityIdentifier("subscription.status.action")
        }
      }
    }.fixedSize(horizontal: false, vertical: true).duckCard()
  }
  private func fact(_ title: LocalizedStringKey, value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.medium) {
        Text(title).foregroundStyle(DuckRole.secondaryText)
        Spacer(minLength: 0)
        Text(value).foregroundStyle(DuckRole.primaryText)
      }
      VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
        Text(title).foregroundStyle(DuckRole.secondaryText)
        Text(value).foregroundStyle(DuckRole.primaryText)
      }
    }.font(.subheadline)
  }
}

/// Essential product facts remain beside the visible paid action while benefits scroll.
private struct DuckProPlans: View {
  let presentation: DuckSubscriptionOfferPresentation
  let actions: DuckSubscriptionActions
  @Binding var preferredPlan: DuckSubscriptionPlan?
  var includesPurchaseButton = true
  var actionTitle: LocalizedStringKey? = nil

  private var selectedPlan: DuckSubscriptionPlan? { presentation.availablePlan(preferred: preferredPlan) }

  var body: some View {
    #if os(macOS)
    HStack(alignment: .bottom, spacing: DuckSpacing.medium) {
      facts.frame(maxWidth: .infinity, alignment: .leading)
      if includesPurchaseButton { purchaseButton }
    }.padding(DuckLook.cardPadding)
    #else
    VStack(alignment: .leading, spacing: DuckSpacing.small) {
      facts
      if includesPurchaseButton { purchaseButton }
    }.padding(DuckLook.cardPadding)
    #endif
  }

  private var purchaseButton: some View {
    DuckSubscriptionPurchaseButton(presentation: presentation, actions: actions,
      preferredPlan: preferredPlan, actionTitle: actionTitle)
  }

  private var facts: some View {
    VStack(alignment: .leading, spacing: DuckSpacing.xSmall) {
      if presentation.pending {
        Text("subscription_note_pending").font(.subheadline).foregroundStyle(DuckRole.secondaryText)
      }
      if let error = presentation.error {
        DuckNotice(title: LocalizedStringKey(error), tone: .failure, symbol: "exclamationmark.circle")
      }
      if !presentation.availablePlans.isEmpty {
        VStack(spacing: 0) {
          ForEach(presentation.availablePlans) { plan in
            if plan != presentation.availablePlans.first {
              Divider().padding(.horizontal, DuckSpacing.small)
            }
            if let price = presentation.price(for: plan) { planRow(plan, price: price) }
          }
        }.background(DuckLook.cardSurface, in: RoundedRectangle(cornerRadius: DuckLook.cardRadius))
        Text("subscription_renewal_note").font(.footnote).foregroundStyle(DuckRole.secondaryText)
      } else {
        Text("subscription_price_unavailable").font(.headline)
        Text("subscription_price_retry_note").font(.subheadline).foregroundStyle(DuckRole.secondaryText)
      }
    }.fixedSize(horizontal: false, vertical: true)
  }

  private func planRow(_ plan: DuckSubscriptionPlan, price: String) -> some View {
    let selected = selectedPlan == plan
    let billingPrice = String(format: NSLocalizedString(plan.priceFormat, comment: ""), price)
    return Button { preferredPlan = plan } label: {
      HStack(spacing: DuckSpacing.small) {
        VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.small) {
              Text(plan.title)
              Spacer(minLength: DuckSpacing.small)
              Text(billingPrice)
            }
            VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
              Text(plan.title)
              Text(billingPrice)
            }
          }.font(.headline).foregroundStyle(DuckRole.primaryText)
          if plan == .annual, let equivalent = presentation.annualMonthlyEquivalent {
            annualDetail(equivalent: equivalent)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "checkmark").foregroundStyle(DuckRole.accent)
          .frame(width: DuckSpacing.medium).opacity(selected ? 1 : 0).accessibilityHidden(true)
      }
      .padding(.horizontal, DuckSpacing.small)
      .padding(.vertical, DuckSpacing.xSmall)
      .frame(minHeight: DuckPreferenceMetrics.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .disabled(presentation.busy || presentation.pending)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("subscription.plan." + plan.rawValue)
  }

  private func annualDetail(equivalent: String) -> some View {
    let monthly = String(format: NSLocalizedString("subscription_annual_equivalent", comment: ""), equivalent)
    return Group {
      if let savings = presentation.annualSavings {
        let recommendation = String(format: NSLocalizedString("subscription_annual_savings", comment: ""), savings)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: DuckSpacing.small) {
            Text(monthly)
            Spacer(minLength: DuckSpacing.small)
            Text(recommendation).fontWeight(.semibold)
          }
          VStack(alignment: .leading, spacing: DuckSpacing.xxSmall) {
            Text(monthly)
            Text(recommendation).fontWeight(.semibold)
          }
        }
      } else {
        Text(monthly)
      }
    }.font(.footnote).foregroundStyle(DuckRole.secondaryText)
  }

}

private struct DuckSubscriptionPurchaseButton: View {
  let presentation: DuckSubscriptionOfferPresentation
  let actions: DuckSubscriptionActions
  let preferredPlan: DuckSubscriptionPlan?
  var actionTitle: LocalizedStringKey? = nil
  private var selectedPlan: DuckSubscriptionPlan? { presentation.availablePlan(preferred: preferredPlan) }
  private var title: LocalizedStringKey {
    if presentation.pending { return "subscription_check_status" }
    if selectedPlan == nil { return "subscription_retry" }
    return actionTitle ?? "subscription_subscribe"
  }
  var body: some View {
    Button {
      if let selectedPlan, !presentation.pending { actions.subscribe(selectedPlan) }
      else { actions.reload() }
    } label: {
      ZStack {
        Text(title).opacity(presentation.busy ? 0 : 1)
        Text("subscription_starting_purchase").padding(.leading, DuckSpacing.medium + DuckSpacing.xSmall)
          .hidden().accessibilityHidden(true)
      }
      #if os(iOS)
      .frame(maxWidth: .infinity)
      #endif
    }.duckPrimaryButton().disabled(presentation.busy)
      .overlay {
        if presentation.busy {
          HStack(spacing: DuckSpacing.xSmall) {
            ProgressView().controlSize(.small).tint(DuckRole.primaryText)
            Text("subscription_starting_purchase").foregroundStyle(DuckRole.primaryText)
          }.font(.body).allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .accessibilityLabel(Text(presentation.busy ? "subscription_starting_purchase" : title))
      .accessibilityIdentifier("subscription.purchase")
  }
}

private struct DuckSubscriptionSecondaryActions: View {
  let presentation: DuckSubscriptionOfferPresentation
  let actions: DuckSubscriptionActions
  var body: some View {
    VStack(spacing: DuckSpacing.xSmall) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: DuckSpacing.medium) { buttons }
        VStack(spacing: DuckSpacing.xSmall) { buttons }
      }.font(.footnote).frame(maxWidth: .infinity)
      DuckSubscriptionRestoreFeedback(state: presentation.restoration)
    }
  }
  @ViewBuilder private var buttons: some View {
    DuckSubscriptionRestoreControl(state: presentation.restoration, restore: actions.restore).disabled(presentation.busy)
    Button("subscription_privacy", action: actions.privacy).buttonStyle(.borderless).accessibilityIdentifier("subscription.privacy")
    Button("subscription_terms", action: actions.terms).buttonStyle(.borderless).accessibilityIdentifier("subscription.terms")
  }
}

enum DuckSubscriptionRestoreState { case idle, restoring, nothingFound, failed }
private struct DuckSubscriptionRestoreControl: View {
  let state: DuckSubscriptionRestoreState
  let restore: () -> Void
  var body: some View {
    Button(action: restore) {
      HStack(spacing: DuckSpacing.xSmall) {
        if state == .restoring { ProgressView().controlSize(.small) }
        Text(state == .restoring ? "subscription_restoring" : "subscription_restore")
      }
    }.buttonStyle(.borderless).disabled(state == .restoring)
  }
}
private struct DuckSubscriptionRestoreFeedback: View {
  let state: DuckSubscriptionRestoreState
  var body: some View {
    Group {
      switch state {
      case .idle, .restoring: EmptyView()
      case .nothingFound: Text("subscription_restore_empty")
      case .failed: Text("subscription_restore_failed")
      }
    }.font(.footnote).foregroundStyle(DuckRole.secondaryText)
      .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("subscription.restore.feedback")
  }
}
