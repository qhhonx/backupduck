# Feature triage

Status: decided by the owner on 2026-10-18 for the rebuild described in
`product-brief.md`. Every current feature on the iPhone and Mac senders, the
Pixel receiver and the browser page falls into one of four outcomes:

- **Keep:** ordinary users see and use it.
- **Automatic:** no control; it behaves correctly by default.
- **Advanced:** kept for fewer people, under Advanced or Diagnostics.
- **Remove:** no longer offered.

"Where it goes" is the target place in the rebuilt apps.

## Brief

| Point | Decision | Note |
| --- | --- | --- |
| How to talk about the Pixel and Google Photos value | Change | Say it boldly; conditions in small print (see brief) |
| Receiver means Pixel only, for now | Agree | |
| No engineering words; `copy-glossary.zh.md` decides | Agree | |
| Settings has at most eight rows | Agree | |

## Sender (iPhone, iPad, Mac)

| Feature | Decision | Where it goes |
| --- | --- | --- |
| Back up new photos automatically | Keep | One switch in Settings; on by default in first run, with one sentence |
| Media types (photos, Live Photos, videos, bursts) | Keep | Auto Backup → Includes; all by default (most people back up videos too) |
| Only specific albums | Advanced | A secondary entry under Includes; all albums by default |
| Back up earlier photos | Keep | A task in first run and the hub; once started it keeps running in the background |
| Scan pause, resume and restart controls | Automatic | Retries by itself; only the task card's pause remains |
| Select photos in the library and back them up | Keep | Library selection mode |
| Send received photos again | Advanced | A photo's More menu |
| Pause backup | Keep | Hub status card |
| Concurrent transfers (1–4) | Automatic | Adapts to network, battery and heat |
| Keep screen on while backing up | Keep | Hub: a contextual switch while a large batch is sending |
| Thumbnail cache limit and clearing | Automatic | Sized from free space |
| Backup temporary files, reserve, auto reclaim | Automatic | Keeps the phone's space safe; the hub explains when space is short |
| Clear temporary files now | Advanced | Advanced → Storage |
| Log retention | Automatic | Fixed at 14 days |
| Activity log (view, export) | Advanced | Settings footer → Diagnostics |
| This device's name | Keep | Settings identity header, Edit |
| Appearance | Keep | Settings, in place |
| Language | Keep | Settings → the system's per-app setting |
| Help | Keep | Rewritten by task |
| Feedback group | Keep | Settings row |
| Receiver network address | Advanced | Connection details |
| "Check connection" button | Automatic | Shown only when the connection fails, with the cause |
| Transfer records and filters | Keep | Under the hub, opened pre-filtered from its summaries |
| Retry failed items | Keep | Automatic retry first, then Retry with the cause |
| Calendar view and grid zoom (iPhone) | Keep | Library |
| Folder sources (Mac) | Keep | Its own sidebar position, simplified |
| Folder include and exclude patterns (Mac) | Advanced | A folder's Advanced |
| Include existing files, back up now (Mac) | Keep | Asked once when adding a folder |
| List thumbnails switch (Mac) | Remove | Thumbnails always show |
| Flat or by-folder file list (Mac) | Keep | A view switch in the Folders toolbar, not a setting |
| Menu bar icon and status menu (Mac) | Keep | Status and pause only |
| Automatic update settings (Mac) | Automatic | Check for Updates in About |

## Pixel receiver

| Feature | Decision | Where it goes |
| --- | --- | --- |
| Start and stop receiving | Advanced | Always on; pause in the hub; stop in Advanced |
| Pause new transfers | Keep | Hub status card |
| Resume after restart | Automatic | Always on |
| Heat protection and threshold | Automatic | Always on with a safe threshold; the hub says "cooling down" |
| Format conversion (Live Photos) | Advanced | Off by default. When a Live Photo cannot be saved as is, that item says so and offers two actions: send feedback, or convert this photo knowing the video loses some quality. The Advanced switch turns conversion on for all |
| Browser access, access code, sign out browsers | Advanced | Advanced |
| Connected devices (view, disable) | Keep | Devices position or a Settings row (D3) |
| Device name | Keep | Identity header, Edit |
| Appearance and language | Keep | Settings |
| Storage budget for received originals | Automatic | Managed from free space; the hub explains when full |
| Minimum free space | Automatic | A fixed safe margin |
| Free up space after saving to Photos | Keep | One switch on the Storage page, on by default to save space; a converted Live Photo always keeps BackupDuck's original |
| Include earlier photos when freeing space | Advanced | Asked once when the switch is turned on |
| Free up space through Google Photos (experiment) | Keep (recommended) | Recommended in Pixel first run and when space runs low, on top of system Smart Storage; still labeled an experiment |
| Read-only Google Photos page check | Remove | Developer builds only |
| Export originals as a zip | Remove | |
| Export Photos records | Remove | Folded into the diagnostics report |
| Log report export and retention | Advanced | Settings footer → Diagnostics; 14 days |
| App updates | Keep | Prompt when available; Check for Updates in the footer |
| Device status card (battery temperature, space, charge) | Automatic | Hidden while normal; one line when hot, full or low |
| Overview (saved, in progress, failed) | Keep | Hub, in plainer words |
| Transfer records, filters, retry | Keep | Opened from the hub |
| Pairing QR code and refresh | Keep | One step in first run |
| Scan a computer's code (Mac sender) | Keep | |

## Browser page

| Feature | Decision | Where it goes |
| --- | --- | --- |
| Receiver management page | Advanced | Reached from the Pixel's Advanced; not redesigned now |

## Meanings confirmed in code

- **Format conversion** applies only to Live Photos. When the Pixel's Photos
  cannot hold the original still and video packaged together, the fallback
  converts them to a compatible format, and the video is re-encoded with some
  quality loss. While it is off, such photos fail to save to Photos.
- **Free up space after saving to Photos.** BackupDuck keeps its own copy of
  each received original, separate from the copy in the Pixel's Photos, so each
  photo takes space twice. With this on, BackupDuck checks the Photos copy, then
  deletes its own copy. Photos copies are never deleted. Items without byte
  evidence, such as older converted Live Photos, are kept.

## Defaults

- **Format conversion is off.** Converting silently could change or compress a
  user's original without their knowing. A photo that needs it is shown as such,
  with feedback and a per-photo, clearly lossy "Convert" action.
- **Freeing space after saving to Photos is on**, so the Pixel does not hold
  every photo twice. Photos copies are never deleted, and a converted Live
  Photo keeps BackupDuck's original.
- These defaults apply to new installs. An existing receiver keeps the choice it
  has: an upgrade never starts deleting BackupDuck's copies on its own. The hub
  may offer to turn freeing space on, with the space it would recover.
