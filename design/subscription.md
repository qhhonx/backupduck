# Apple subscription experience

## Purpose and scope

The subscription page answers what a person receives, what they will pay, when
payment starts, and how to restore or manage the purchase. It is a supporting
guided decision, not a new navigation position or an account system.

Only production App Store distribution enables Pro entry points, purchasing and
the seven-day access constraint. TestFlight, Xcode/development and direct-download
hosts retain their existing backup capabilities without Pro entry points or
welcome-period enforcement. A store-target build flag alone is insufficient:
TestFlight and production can use the same uploaded build.

The host enables Pro only after StoreKit verifies an app transaction belonging
to this bundle in the production environment. Sandbox, Xcode, unverified and
missing transaction data do not enable Pro. Resolve distribution asynchronously
on each application launch; retry an unresolved result on foreground entry.
Unresolved distribution never pauses backup, opens a purchase page or starts an
expiry clock. Do not persist distribution as a permanent preference or reuse
old store welcome state to restrict a TestFlight/direct-download installation.
Receipt absence is not evidence of production distribution. Detection uses
`AppTransaction.shared` without an explicit receipt-refresh or authentication
fallback. The direct-download Mac
host does not query StoreKit for distribution.

Eligible Apple store senders provide one seven-day complimentary welcome period before
purchase. Welcome access and paid access have the same backup capabilities and
no transfer quota. The welcome period is not an Apple subscription: it requires
no purchase confirmation, does not renew and never charges when it ends.
Continuing any unfinished backup or starting new backups afterward requires
a monthly or annual auto-renewable subscription, confirmed explicitly in Apple’s
purchase interface. There is no
additional introductory subscription trial. The Android receiver
does not display a purchase requirement. Direct-distribution Mac builds do not
infer store purchasing support from their bundle identifier.

The App Store supplies the localized subscription price and period. An unknown
price is never replaced with a guessed price. A welcome end date is shown only
when known; the purchase interface does not invent welcome eligibility or dates.
The two periods share the same Pro benefits and subscription level. The annual
plan charges the full annual price at purchase and at each renewal. Purchase and renewal use Apple services; the application does not
require a separate account, photo relay or online usage-metering service.

## Entry and navigation

Settings has one Pro entry below the device identity, separate from device and
backup preferences. It is a quiet navigation row in every access state; there
is no additional introduction card or nested action. Use the shared settings
icon tile with one stable crown symbol, including when selected. Native list
selection owns contrast, not a replacement brand asset. Preference rows use
the shared 52 pt iPhone and 41 pt Mac metrics. The entry opens the current
access facts, included capabilities and the available plans and purchase action together.
The unsubscribed entry uses a concise Upgrade action label rather than a long
Not Subscribed status. Other entries retain their relevant access summary. The
Mac row gives the Pro name its natural width before laying out that trailing
text. At the normal settings-column width both the name and unsubscribed action
stay on one line. Larger text and longer access summaries may grow the row
instead of shrinking type or clipping information.

Onboarding completes without a purchase page, Apple purchase confirmation or
an added subscription step. Welcome access permits the first backup and the
chosen automatic-backup setting. While access is valid, new backup actions do
not open an offer. After access ends, the working page explains that backups
are paused until subscription; a deliberate Continue Backup action may open the offer.
Launch, background discovery and expiry never present an offer automatically.
Browsing photos, opening information, reading history, exporting
existing results and reconnecting a receiver never open a purchase page by
themselves. Returning from the offer preserves input, selection and source.

### Backup task entry

For a paired, ready sender whose unfinished backup is held by expired access,
the existing overall-state card explains Pro expiry, the paused backup and
retained content/progress. Its one primary action is Subscribe & Continue.
Use the shared state-card composition: action below the explanation on iPhone,
intrinsic-width trailing action on Mac. Do not add a promotional card above an
otherwise active-looking backup status, repeat the expiry notice elsewhere or
show item totals inside the subscription explanation.

The rest of the task page keeps its known progress, recently saved photos and
Backup History. Historical progress remains a task fact, with no animated
working claim while access is blocked. Start, Pause and Resume controls for
backup execution are not offered as an alternative around the access constraint;
read-only history and photo viewing stay available. Access expiry does not edit
the person's queue-pause intent or saved automatic-backup preference.

The offer opens only from a deliberate tap or click on the state-card action.
Opening the backup page or receiving an expiry update never presents it. Use
the same offer content and fixed product facts as the Pro page. Dismissing the
offer, cancelling purchase or encountering purchase failure retains the backup
page, selected receiver, progress and scroll position. The action remains
available for a later retry. Only verified access can make work eligible to
continue, still subject to the person's pause, permissions and connection.

On iPhone, a contextual offer uses the shared system sheet. Its one Done
confirmation-role item is trailing; the purchase action stays in a fixed bottom
area above native bars and the safe area. A Settings detail uses native push and Back. On Mac, Settings
keeps its category list and replaces the detail pane; a contextual offer is an
attached sheet with native Cancel and a default purchase button at bottom
trailing. The sheet title, frame and controls follow `platform-expression.md`.
The actual Apple purchase confirmation and subscription-management interface
remain system-owned and are never drawn by the app.

## Offer composition

1. A compact, centered identity uses the existing premium duck, the Pro name
   and one short value statement. Fit the visible illustration optically so
   transparent asset margins do not create an empty header. The lead states
   original-quality transfer without item or transfer quotas. Do not repeat this
   line in the purchase area. Use one duck per visible page and no decorative motion.
2. When access facts are available, place one compact current-state group below
   the identity. State, known dates and the relevant consequence belong together,
   not in a date-only card with detached actions or footnotes. Expired access
   explains the pause and retained backups/progress without item totals; detailed
   counts belong on the backup task page.
3. One solid grouped benefit surface explains the capabilities people choose
   the app for: preserving Live Photo motion resources; automatic, quiet backup
   of new photos; background transfer; and completing a large library without
   an application item quota. Mac adds importing photos and videos from folders,
   drives, SD cards and already-mounted NAS folders. This is readable mounted
   folder access, not a hosted or NAS receiver product. iPhone has four rows;
   Mac has the same four followed by its source-import row. Do not advertise
   folder sources on iPhone or promote iCloud retrieval as another primary
   benefit. Each row has a fixed monochrome symbol column, a
   short semibold title and one secondary explanatory sentence. Dividers start
   at the text column. These are included capabilities, not separate paid tiers
   or claims that freely accessible browsing and export require payment.
   The main Live Photo copy describes preserving originals and paired motion,
   not universal gallery playback or cloud completion. Format-specific details
   belong in the relevant help and actionable media state, rather than diluting
   the short benefit description.
   iPhone background uploads and original preparation follow system scheduling,
   without a continuous lock-screen or force-quit guarantee. Mac can keep working
   with its window closed while the app runs; quitting stops work. Completing
   a large library remains subject to current access and does not grant a batch
   permission to continue beyond expiry. Folder backup covers supported media,
   not RAW files,
   arbitrary documents or recreated Google Photos album hierarchy.
4. A fixed, compact purchase area lists the available monthly and annual plans,
   their full localized billing prices, one legible explanation of Apple billing,
   automatic renewal and cancellation, and the native purchase action. Present plans as grouped
   selection rows with the platform's selected state and a checkmark.
   When both StoreKit prices establish at least one percent savings against
   twelve monthly payments in the same currency, place annual first and select
   it initially. Put the recommendation and whole-percent savings below the
   annual billing total alongside its monthly equivalent. Keep the total the
   most prominent price. Both choices and the action remain visible on initial
   presentation at the default text size.
   Welcome access is described separately from paid subscription. Unlimited
   means no application transfer quota, never unlimited cloud storage or device
   capacity. Cloud-service and Pixel-model explanations belong in the relevant
   help, not in the Pro benefits or subscription explanation.
5. The primary action subscribes to the selected period at its displayed price. Opening the
   page does not start a purchase. Product loading, cancellation, pending approval and
   failure remain distinct; no unverified result grants paid access.
6. Restore Purchases, Privacy and Terms remain available as secondary actions.
   Privacy opens the published policy, which links to the Pro subscription terms.
   Terms opens the applicable Apple end-user agreement directly. Ordinary copy
   never exposes purchase identifiers or verification
   mechanisms.

Identity, access facts, benefits and secondary actions form a scrollable content
column. The purchase area stays visible separately, without duplicating its price,
terms or action in that column. On iPhone, align both areas to shared page margins
and keep the fixed area above the native tab bar and safe area. On Mac, center
one bounded column, align the fixed purchase area to its edges and use an
intrinsic-width native trailing button. Contextual sheets preserve the same
first-viewport access to price, renewal terms and purchase action.

At narrow widths and the first larger text size, keep the purchase action fully
visible on initial presentation. Larger accessibility text may grow the purchase
area; preserve readable billing terms and native dismissal controls. Decorative
identity spacing yields before essential facts and actions. Benefits remain
scrollable, including their last row and the secondary legal actions.

## Subscription facts and next action

The detail starts with the current state, followed by known dates and price,
within the shared Pro composition. Welcome and expired states retain the same
meaningful benefit section as the purchase offer; they are not sparse intermediate
pages that require another step to learn what access includes. Welcome and new
visitors see capabilities with the optional purchase area already visible.
Expired access puts paused-work facts above the benefits and keeps the direct
paid-resume action visible in the fixed purchase area.
An existing paid member sees access facts and management before secondary benefit
information.
Do not repeat state, dates, price or the primary action in several sections.

| State | Facts and next action |
| --- | --- |
| Checking | Say the purchase state is being checked. Retain still-valid verified access; a failed connection alone does not establish expiry. |
| Welcome | Show the known free-access end and that it will not charge automatically. Included benefits and the initially visible optional purchase area share the same page; no Manage Subscription action exists for a purchase that has not happened. |
| Active | Show the known next renewal and current subscription facts; offer Manage Subscription. |
| Renewal off, access valid | Show when access ends; retain full access through that date and offer Manage Subscription. |
| Expired | Put the known end date, paused unfinished-work consequence and retained progress in one state group. Provide the available plans and direct subscription action without a separate Learn More step; saved results remain accessible. |
| Pending approval | Say confirmation is pending; offer a status check without claiming success or repeatedly starting a purchase. |
| Store unavailable or failed | Show an actionable cause and Retry. Retain selection and existing valid access. |

Restore is an explicit user action. Its progress and failure appear in place;
an empty restore result is not a successful new subscription. Management does
not cancel, renew or change a plan until the person acts in Apple's interface.
Missing dates remain absent. A current subscription does not prove anything
about receipt, gallery publication or cloud upload.
Idle restoration does not reserve a large blank feedback area or separate the
current-state consequence from its facts. Active restoration feedback keeps
stable local geometry while that operation runs.

## Backup continuity

Backup execution requires current welcome or paid access. When access ends,
unfinished backups pause, including the remaining items of a previously
accepted whole-library backup. Earlier submission does not extend access.
Preserve registered scope, pending preparation, queued work and recorded progress
in their existing durable owners. Do not discard or recreate the work, or create
a second subscription queue. A confirmed subscription makes that work eligible
to resume, subject to the person's existing pause, permissions and connection.

Access expiry is a separate execution constraint: do not change the saved
automatic-backup preference or represent it as the person's queue-pause action.
Stop new preparation and transfer at a safe boundary, retaining completed data
and recoverable partial state. In-flight completion observations and local
bookkeeping still reconcile facts; they do not authorize another backup item.
Compact status surfaces reflect the execution hold rather than claiming active
backup. The Mac menu cannot bypass it with Pause or Resume. End the iPhone Live
Activity when access closes; its lock-screen Resume action cannot grant access.
Receiver identity, source revision and recorded results retain their existing
owners across purchase, cancellation, restart and expiry.

Read-only browsing, existing originals, history, export and necessary recovery
remain usable after access ends. Retrying unfinished backup work also requires
current access; no retry grants an exemption from expiry. Renewing access does
not prove that any photos were backed up during the inactive period.

## Catalog coverage

Use the shared views with injected synthetic data and action executors for
known and unavailable prices, checking, welcome, active, renewal off, expired,
pending, unavailable, purchase failure and restoration. Catalog buttons never
perform a real purchase. Record synthetic dates and prices with the evidence;
they are not production readings. Inspect iPhone and Mac in light and dark,
narrow widths, the first larger text size and long localized content.
Catalog preview injection is separate from runtime distribution verification.
Include TestFlight and direct-download fixtures with subscription data present
but Pro disabled: ordinary backup remains available, Settings has no Pro entry
and the hub has no subscription pause or offer. Sandbox purchase success is not
production-distribution evidence.

## Local purchase testing

Interactive purchase testing uses an independently installed development host
with its own application identity and storage. An explicit testing-only compile
condition and that identity are both required to enable the local store. Normal
App Store, TestFlight and direct-download targets contain no local purchase
controls. The test host uses the production views, sender and entitlement
adapter; it does not substitute fixture alerts for Apple's purchase interface.

The local configuration contains both billing periods without an
introductory offer. Testing controls distinguish app-granted welcome access
from Apple transactions. Test transactions may exercise purchase, pending
approval, cancellation, restoration, renewal and expiry without real payment.
The host verifies the local store environment before allowing purchase and
never falls back to an account-backed purchase when local testing is absent.
Synthetic welcome dates and store transactions remain visibly identified in
the testing controls and never modify another installation's access or data.
