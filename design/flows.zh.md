# Main flows: Chinese copy

Translation of `flows.md` with the Chinese interface copy as drafted for review (zh-Hans).
The English `flows.md` is the primary document; implemented strings live in
`Localizable.strings` and `strings.xml`.

Status: proposed, for review. These are the three journeys of
`product-brief.md`: first run, every day, and when something goes wrong. They
follow `feature-triage.md` and the interaction standards (`interaction.md`).

Copy is drafted in Chinese because it is the primary review language; English
follows the same structure. Words follow `copy-glossary.zh.md`.

## Principles

- **Say the whole journey first.** One screen names the three steps with three
  distinct marks that recur on every later step: a yellow circle, the blue wing
  and an orange sparkle, sized to the same visual weight.
- **One decision per screen, primary action in a fixed place.**
- **Explain before the system asks.** Camera, photos and notifications each get
  one sentence of why, then the system prompt. Refusing never blocks the
  journey; the hub shows what is missing.
- **Show value early.** The first photo landing on the Pixel is the first
  reward. Notifications are asked after it, not before.
- **Partial results count.** What is already safe is shown while the rest
  continues, with honest counts.
- **Link like a desktop app is linked.** The device being added shows a code;
  the device you already hold scans it.
- **Space actions show their effect and consequence together** ("Free 3.2 GB ·
  your photos stay in the Pixel's Photos").
- **The duck appears for brand moments only** (welcome, connecting, empty, done,
  all caught up), never on errors or warnings.

## 1. First run

### iPhone (and Mac)

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** Headline: "比 iCloud 大，比 NAS 简单，而且免费。" Subline: "一台旧 Pixel，把你所有的照片备份进 Google 相册，原画质、不限量。" Steps: ① 在 Pixel 上装好备份鸭 ② 扫码连接两台设备 ③ 照片自动备份到 Google 相册 · 免费、不限量. Small print: "一代 Pixel 原画质无限，二到五代“节省空间”画质无限，权益由 Google 提供。" Welcome duck | 开始 | The bold value line follows the brief |
| 2 | **Install on the Pixel.** A QR code that opens the Pixel download page in the Pixel's camera; the address as text below | 已经装好了 | Skipped if a Pixel was paired before |
| 3 | **Connect.** One sentence on why the camera is needed, then the scanner. On success: "已连接 Pixel 8 Pro" with the connecting duck | 扫描 Pixel 上的码 | Mac shows its own code for the Pixel to scan instead |
| 4 | **Photos.** "备份鸭需要读取你的照片，直接送到你的 Pixel，不经过我们的服务器。" then the system prompt | 继续 | Limited access: say what will and won't back up |
| 5 | **What to back up.** Auto Backup on (switch shown on), with when it runs: "iPhone 和 Pixel 连着同一个 Wi‑Fi 时自动备份". "也备份以前的 12,384 张照片吗？约 86 GB，再多也能全部备份完。" No Pixel free-space figure: the Pixel frees space as it goes | 全部备份 | Secondary: 只备份以后的新照片 |
| 6 | **First photo lands.** The first thumbnail travels to the Pixel mark, then "第一张照片已经存进 Pixel 相册". One orchestrated motion; static under Reduce Motion | 好 | Then one sentence on notifications ("只在需要你处理时提醒你") and the system prompt |
| 7 | **Hub.** Progress card for earlier photos, keep-screen-on switch while a large batch runs, Live Activity on the lock screen | — | First run ends here |

### Pixel

| Step | Screen | Primary action | Notes |
| --- | --- | --- | --- |
| 1 | **Welcome.** The same headline as the iPhone, "比 iCloud 大，比 NAS 简单，而且免费。" Subline: "这台旧 Pixel 接收你 iPhone 里的照片，原画质备份进 Google 相册，不限量。" The same three marks and small print | 开始 | |
| 2 | **Keep it running.** Stay on Wi‑Fi; allow notifications and battery exemption so receiving keeps going. Plugging in is suggested as optional | 允许 | Each system prompt explained first |
| 3 | **Pairing code**, full screen: "用 iPhone 上的备份鸭扫描这个码". Secondary: 连接 Mac（扫描 Mac 上的码） | — | The screen blocks screenshots, as today |
| 4 | **Connected.** "已连接 Lin's iPhone" | 下一步 | |
| 5 | **Google Photos.** "照片会存进这台 Pixel 的相册。打开 Google 相册的备份，它们才会上传。" | 打开 Google 相册 | Secondary: 已经开启了. We cannot read Google Photos' backup state, so we never claim it is on |
| 6 | **Free space automatically.** System Smart Storage shown as on (it removes photos Google Photos has backed up; on by default on the test Pixel XL). Recommends turning on auto cleanup (experiment): "空间紧张时，备份鸭替你在 Google 相册里点“释放空间”。需要无障碍权限，只用于这一件事。" | 开启自动回收 | Secondary: 以后再说. Offered again when space runs low |
| 7 | **Hub**: waiting for photos, with the empty duck | — | |

## 2. Every day

The hub answers "are my photos safe?" in one line, then shows only what is
happening or needs the user.

### iPhone hub states

| State | Top line | Below |
| --- | --- | --- |
| All caught up | "全部照片已存进 Pixel 相册" · last backup time | Latest photos strip; the all-caught-up duck |
| Backing up | "正在备份 128 张 · 约 2.1 GB" with progress | Current photo thumbnail; keep-screen-on switch above a size threshold; Pause |
| Earlier photos | Task card "以前的照片 3,210 / 12,384" | Runs in the background once started; pause only |
| Waiting for the Pixel | "等 Pixel 回到 Wi‑Fi 后继续" | New photos are kept in order; no action needed |

- **A photo's state** says only what we know: "已存进 Pixel 相册 · 今天 10:42", or
  "已收到，正在存进相册", or the cause of a failure. Google Photos' state is not
  available to us, so it is not shown per photo; it appears in first-run setup
  and in Help ("打开 Google 相册查看"). We never claim cloud backup.
- **Lock screen:** a Live Activity while a batch runs: count left, progress
  ring, pause. It ends when the batch ends.
- **One switch, several conditions.** Auto Backup stays a single switch for
  ordinary users. Its page states when it actually runs ("iPhone 和 Pixel 连着同一个
  Wi‑Fi 时自动备份"), and when a condition is not met the hub names that condition
  instead of a generic "paused" (see section 3).
- **Rating** is asked once, at the moment earlier photos finish backing up, after
  the user has seen the result. Never
  during first run or after a problem.
- **Notifications** only when the user is needed or a long task finishes:
  earlier photos all backed up; the Pixel unreachable for 24 hours; Pixel
  storage full; a photo needs conversion. No routine "backed up" notices.

### Pixel hub states

| State | Top line | Below |
| --- | --- | --- |
| Receiving | "正在接收 Lin's iPhone 的照片 · 还剩 34 张" | Latest items |
| Idle | "今天收到 128 张，都已存进相册" | Space card when relevant |
| Space freed | "已释放 3.2 GB，照片仍在相册里" | Shown after freeing runs |

Device readings (temperature, space, battery) stay hidden while normal and
appear as one line when they matter.

### Hub rules (implemented in the catalogs, approved October 18, 2026)

- One state at a time, in this order: not paired, opening, paused, problems,
  backing up or receiving, caught up, empty. Pausing is the user's choice and
  outranks problems, because nothing is checked while paused.
- "全部照片已存进 Pixel 相册" appears only when every received
  photo is saved there. Otherwise the hub says "照片都已送到 Pixel" and
  "还有 4 张正在存进 Pixel 相册" (P3).
- The keep-screen-on switch appears only while 50 or more photos remain.
- The Pixel shows free space only in the space card, or as a hint when less
  than 15% remains and auto cleanup is off. Readings are the device's own.
- The Pixel hides recent items until something has been received, and hides
  them while receiving is off or no device is paired.
- First run: the title follows the flight, so the screen never says the photo
  landed before it is seen landing. Reduce Motion adopts the settled state in
  one frame.

## 3. When something goes wrong

Each problem says the cause, what happens by itself, and at most one action. It
appears in the hub of the device where the user can act, and on the affected
items. It becomes a notification only when it lasts.

| Problem | Where | What the user reads | Happens by itself | Action |
| --- | --- | --- | --- | --- |
| Pixel unreachable | iPhone hub | "连不上 Pixel 8 Pro。新照片会先排好，Pixel 回来后自动继续。" | Retries; resumes in order | 怎么办 → checks with the likely cause first (same Wi‑Fi, Pixel on, app running) |
| Pixel storage full | Both hubs | Pixel: "空间快满了，已暂停接收。Google 相册已经备份好的照片可以从这台 Pixel 上删掉，约 18 GB；照片仍在 Google 相册的云端。" iPhone: "Pixel 空间不足，暂停中。" | Resumes when space returns | Pixel: 开启自动回收 · 去 Google 相册释放空间 |
| Photo access off or limited | iPhone hub | "备份鸭看不到你的照片。" / "只能看到你选的照片。" | — | 打开设置 |
| Live Photo needs conversion | The item, and a hub line with a count | "这张实况照片不能原样存进 Pixel 相册。" | Kept safely on the Pixel; not converted | 转换后存进（视频画质会下降） · 反馈给我们 |
| Pixel no longer trusts this iPhone | iPhone hub | "Pixel 不再认识这台 iPhone，需要重新扫码连接。" | Pauses | 重新连接 |
| Not enough space on the iPhone to prepare photos | iPhone hub | "iPhone 空间不够准备照片，已暂停。" | Resumes when space returns | 查看 iPhone 储存空间 |
| Pixel too hot | Pixel hub; iPhone status line | "Pixel 太热了，降温后自动继续。" | Resumes after cooling | — |
| Running in the background on iPhone | iPhone hub while a batch waits | "备份鸭在后台会慢一些，打开它可以传得更快。" | Continues when the system allows | Keep-screen-on switch |

Every failure message comes from the same state the item shows, so the hub,
the item and any notification never disagree (P3).

## Platform notes

- The Pixel apps use Material 3's standard navigation bar and monochrome icons,
  per the constitution's platform layer.
- Mac settings keep a limited line width in the detail pane; the photo viewer
  opens in its own dark window.

## Open

- The Pixel download page (step 2) needs a stable address and a page for the
  APK; it is outside the apps.
- D3 is closed (October 18): Devices is the identity header and a Settings row.
- Live Activity and Mac menu bar details are designed with the hub.

## How the Pixel keeps space free

The copy in the Pixel's Photos stays on the Pixel until Google Photos has
uploaded it and the device copy is removed. BackupDuck cannot see which photos
Google Photos has backed up, so only Google's own tools can remove them safely:

1. **System Smart Storage** (baseline): removes backed-up photos automatically.
   Confirm on the device whether its age rule counts from capture or backup
   before describing it in copy.
2. **Auto cleanup (experiment, recommended)**: BackupDuck taps Google Photos'
   "Free up space" through the accessibility service when space runs low.
   Google still decides what is safe to remove. It needs a clear consent screen
   and stays an experiment until it proves reliable across Google Photos
   versions.

BackupDuck's own copy is freed separately by "free up space after saving to
Photos" (`feature-triage.md`).
