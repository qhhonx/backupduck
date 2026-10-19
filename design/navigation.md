# Navigation skeleton

Status: proposed, for review (October 2026). Redesign of the root navigation on
iPhone, Mac and Pixel (`constitution.md` § Information architecture,
§ Redesign before refinement). It also proposes an answer to D3.

## 1. The user's question

"Where do I look?" An ordinary user comes back to the app for three reasons:

1. **My photos**: look at them, see which are backed up.
2. **Is the backup working?**: the hub, and from there the history.
3. **Change something**: settings, rarely.

Devices are visited when pairing and almost never after. Records are a detail
of the hub, not a destination of their own. Storage on the Pixel matters only
when space runs low, and the hub already says so.

## 2. References

| Product | Root navigation | Devices and storage |
| --- | --- | --- |
| Google Photos | Photos, Collections (plus Search) | Backup and device storage under the account menu |
| iOS Photos | Library, Collections | iCloud and storage in system Settings |

Common pattern: the content is the first destination, the status is one place,
and devices and storage live in settings.

## 3. Proposal

| Position | iPhone (tab bar) | Mac (sidebar) | Pixel (Material 3 navigation bar) |
| --- | --- | --- | --- |
| Content | Photos (the library, with backup marks once Library is redesigned) | Photos: Photo Library, Folders | Photos (received photos, `records.md`) |
| Hub | Backup (hub; history opens from it) | Backup: Overview, History | Receive (hub) |
| Settings | Settings (devices in the identity header) | Settings (devices in the identity header) | Settings (devices, storage) |

- **Three positions on every platform.** The phone tab bar drops from four tabs
  to three; the Mac sidebar from three sections and six rows to two sections
  and five rows; the Pixel bar from four destinations to three.
- **D3: Devices do not keep their own position.** The paired Pixel (or, on the
  Pixel, the paired iPhones and Macs) is the identity header's subtitle in
  Settings and opens the device page. Pairing another device starts there and
  from first run. A problem with the device appears on the hub, where the user
  already looks.
- **Records are not a destination on the phone.** History opens from the hub.
  The Mac keeps History as a sidebar row under Backup, because a desktop
  sidebar shows sub-pages that a phone keeps one level down.
- **Pixel storage moves into Settings and the hub.** Running out of space is a
  hub problem card with its actions; the detailed storage page is a settings
  row. "Photos" replaces "Transfers".
- **Names** follow `copy-glossary.zh.md`; the zh-Hans labels are in the
  strings files (`nav_*`, `mac_nav_*`).

## 4. What this replaces

| Platform | Legacy | Proposed |
| --- | --- | --- |
| iPhone | Library, Backup, Receiver, Settings | Photos, Backup, Settings |
| Mac | Sources (System Library, Folders), Backup tasks (Overview, Transfers), Manage (Receiver, Settings) | Photos (Photo Library, Folders), Backup (Overview, History), Settings |
| Pixel | Receive, Transfers, Storage, Settings | Receive, Photos, Settings |

## 5. Open

- The device page itself (what it shows for one or several peers) is redesigned
  separately; until then the identity header opens the legacy device page,
  recorded as a remnant.
- Whether the Photos tab carries backup marks is decided with the Library
  redesign.
