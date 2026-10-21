# Page register

The overall plan and phase status are in `redesign-roadmap.md`.

Which pages are redesigned for ordinary users and which are still legacy
(`constitution.md` § Redesign before refinement). Update this file in the same
change that redesigns a page, removes a remnant or adds a page.

- **Redesigned**: went through the four steps and its structure, flow and copy
  were approved in review. Its look is approved separately through the visual
  language (`visual-language.md`); until then no page is final.
- **Legacy**: the earlier app's page. Defect fixes only; anything else starts
  with a redesign.
- **Remnant**: a legacy page or component that a redesigned page opens or
  embeds. It blocks migration of that page until it is redesigned.

Audit of October 18, 2026, covering every page touched since the redesign began.

## Shipped in the apps (October 19, 2026)

The redesigned pages are the default in the iPhone, Mac and Pixel apps
(roadmap step 6). The earlier pages remain in the code only for the design
catalog's comparison switch and are removed in the cleanup that closes step 6.
New since the canvas review: the device page (iPhone, Mac), help by task and by
problem (iPhone, Mac), the photo's backup facts in the library viewer (iPhone,
Mac), and the Pixel's Storage page.

## Redesigned (structure approved)

| Page | Platforms | Approved | Remnants |
| --- | --- | --- | --- |
| Settings root and its new pages (Auto Backup, Appearance, Language, About, Advanced) | iPhone, Mac, Pixel | Oct 18 | Device page behind the Devices row (`IOSReceiverPage`, Mac receiver page); help center (`BackupHelp`, `ReceiverHelpActivity`); album chooser (`BackupScopeEditor`); device name sheet (`DeviceNameEditor`); Mac update panel (`UpdateSettings`); Pixel devices list, browser access (`DashboardAccessUI`), check for updates (`UpdatesActivity`) |
| First run | iPhone, Pixel | Oct 18 | Pixel auto cleanup opens the legacy experiments page (`ExperimentsActivity`) |
| First photo flight | iPhone | Oct 18 | None |
| Backup hub | iPhone, Mac | Oct 18 | None once Mac connect is approved |
| Receive hub | Pixel | Oct 18 | Recent item rows and records (`TransferAdapter`, `HistoryPage`); pairing (`PairingUI`); auto cleanup (`ExperimentsActivity`); problem help (`ReceiverHelpActivity`) |
| Navigation skeleton (`navigation.md`; D3: Devices is a Settings row) | iPhone, Mac, Pixel | Oct 18 | Legacy device pages behind the Devices row; legacy Pixel storage page behind the Storage row |
| Connect and reconnect | iPhone | Oct 18 | None (Mac and Pixel pairing are still legacy) |

Diagnostics (`ActivityLogView`, report export) are intentionally technical and
reached only from the settings footer, so they are not remnants.

Copy remnants found and fixed in this audit: "Thumbnail Cache" (now
"Thumbnails"), "Receiver paired" (now "Pixel connected"), "Pair First" (now
"Not Connected") and the Pixel hub's loading line, which said "tasks".

## Approved October 19 (canvas review), built behind the design switch

The owner approved the overall direction, including these structures, on
October 19; details are adjusted in native review.


| Page | Platforms | Contract | State |
| --- | --- | --- | --- |
| Records and photo detail | iPhone, Mac, Pixel | `records.md`, `library.md` | Owner review: the repeated Google Photos line is now a single footer on all three; on iPhone and Mac the owner asked how this grid relates to the library, answered by `library.md` (one grid). Built in all three catalogs (`BackupHistoryView`, `PhotoBackupDetail`, `ReceivedPhotosPage`). Pixel remnant: the hub's recent rows still use the legacy row; Pixel problem cards have no thumbnails until the core can return a preview of a received original |

| Mac connect (`mac-connect.md`) | Mac | `mac-connect.md` | Built behind the design switch; replaces `MacPairingSheet` in the proposed design |
| Pixel connect and devices | Pixel | `pixel-connect.md` | Built behind the design switch: one connect flow shared by first run, the hub and Settings, a Mac direction, and a devices page (Stopped, never Remove). Once approved, `PairingUI` and the legacy device list stop being remnants |
| Library backup views and marks | iPhone, Mac | `library.md` | iPhone views and tile marks built behind the design switch and checked on the iOS Simulator with a synthetic library; Mac has the views, legacy marks |

## Approved October 21, not built

| Page | Platforms | Contract | State |
| --- | --- | --- | --- |
| Folders, Settings › Folders, add folder, file rules, stop folder | Mac | `mac-folders.md` | Structure approved (F0–F9). The existing folder page in the app is legacy until rebuilt from this contract |
| Photo information | iPhone, Mac, Pixel | `platform-expression.md` A8 | One viewer and one information layout per platform; backup history opens the same viewer instead of a separate detail sheet |

## Legacy

Ordered by how often an ordinary user meets the page. Devices, Album chooser,
Help center and the Pixel's Storage page received a new design in the October 19
canvas review and are rebuilt in roadmap step 3; the others follow the standards
in step 4.

| Page | Platforms | User's question to start from |
| --- | --- | --- |
| Devices | iPhone, Mac | Which Pixel do my photos go to, and is it there? (D3) |
| Storage and auto cleanup | Pixel | Is this Pixel running out of space, and is freeing it safe? |
| Album chooser | iPhone, Mac | Which photos are included? |
| Help center | All | Why is this happening and how do I fix it? |
| Menu bar and status menu | Mac | Is a backup running right now? |
| Notifications | All | Only when the user is needed (`flows.md` § Every day) |

Work done on legacy pages before this rule (records and detail strings, record
scenarios, Live Photo wording) only reworded the legacy structure. It does not
count as redesign. The redesign of each page decides what of it to keep.
