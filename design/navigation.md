# Navigation skeleton

## 1. The user's question

"Where do I look?" An ordinary user comes back to the app for three reasons:

1. **My photos**: look at them, see which are backed up.
2. **Is the backup working?**: the hub, and from there the history.
3. **Change something**: settings, rarely.

Devices are visited when pairing and almost never after. Records are a detail
of the hub, not a destination of their own. Storage on the Pixel matters only
when space runs low, and the hub already says so.

The content is the first destination, the status is one place,
and devices and storage live in settings.

## 2. Navigation

| Position | iPhone (tab bar) | Mac (sidebar) | Pixel (Material 3 navigation bar) |
| --- | --- | --- | --- |
| Content | Photos (the library, with backup marks) | Photos: Photo Library, Folders | Photos (received photos, `records.md`) |
| Hub | Backup (hub; history opens from it) | Backup: Overview, History | Receive (hub) |
| Settings | Settings (devices in the identity header) | Settings (devices in the identity header) | Settings (devices, storage) |

- **Three positions on every platform.**
- **Devices belong in Settings.** The paired Pixel (or, on the
  Pixel, the paired iPhones and Macs) is the identity header's subtitle in
  Settings and opens the device page. Pairing another device starts there and
  from first run. A problem with the device appears on the hub, where the user
  already looks.
- **Records are not a destination on the phone.** History opens from the hub.
  The Mac keeps History as a sidebar row under Backup, because a desktop
  sidebar shows sub-pages that a phone keeps one level down.
- **Pixel storage belongs in Settings and the hub.** Running out of space is a
  hub problem card with its actions; the detailed storage page is a settings
  row. The photo grid is named "Photos".
- **Names** follow `copy-glossary.zh.md`; the zh-Hans labels are in the
  strings files (`nav_*`, `mac_nav_*`).

