# Copy glossary (zh-Hans)

The Chinese interface vocabulary, with each term's English counterpart. It is a
localization reference, so Chinese examples appear inline.

Status: proposed, for review. These are the product-layer words. Once they are
approved, every platform uses them, and the current strings are migrated page
by page with the redesign. 

## Principles

- **Use the user's words, not the mechanism.** People think in photos, their
  phone, their Pixel and the Photos app, not in originals, receivers, receipts
  or queues.
- **Use the platform's own word when one exists.** iOS Photos says 原片 /
  "Originals"; Android says 释放空间 / "Free up space"; everyone says Wi‑Fi.
- **Name the device.** "Backs up to Pixel 8 Pro" is clearer than "the receiver".
  Use the generic word only when no device is known.
- **Show results, not process steps.** Verification, receipts and scanning are
  not shown as nouns. Show the result ("Received in full", "Saved to Photos"),
  or explain the step in Help.
- **Short labels, one-sentence footers** (`settings.md`). Engineering detail
  goes to Help.
- Receipt, phone-gallery publication and cloud upload stay three distinct facts
  (P3). Only their words change.

## Terms

| Current (zh / en) | What it means | Proposed zh | Proposed en | Notes |
| --- | --- | --- | --- | --- |
| 原件 / original | The full-quality photo or video file, as opposed to thumbnails | 原片 | original | Matches iOS Photos (下载并保留原片). Use 原片和视频 only where video matters |
| 原件传输 / 原件准备 | Exporting the file from the library and sending it | 传输 / 准备照片 | sending / preparing | Users see one task: sending the photo |
| 接收端 / receiver | The device that receives backups | 接收设备; device name when known | receiving device; device name | "Backs up to Pixel 8 Pro" |
| 发送端 / sender | The phone or computer that sends | 发送设备; device name | sending device; device name | |
| 发布到设备图库 / published | Saved into the Pixel's Photos (gallery) | 存进相册 | saved to Photos | "已存进 Pixel 相册" / "Saved to the Pixel's Photos" |
| 回执 / receipt | The receiver's confirmation | not shown; 已收到 | not shown; received | Keep the meaning, drop the noun |
| 校验 / verified | Integrity check of a received file | not shown; 已完整收到 | not shown; received in full | Only failures mention it ("文件不完整，会重新发送") |
| 处理 / processing (receiver) | Saving into Photos, conversion, etc. | name the step: 正在存进相册 / 存进相册失败 | saving to Photos / couldn't save to Photos | "处理失败" says nothing |
| 扫描 / scanning (history) | Looking through the existing library | 正在查看以前的照片 | looking through earlier photos | |
| 历史导入 / existing photos | Backing up photos from before automatic backup | 以前的照片 | earlier photos | Matches the new Auto Backup footer |
| 队列 / queue | Items waiting to send | 等待传输 | waiting to send | |
| 任务 / task | One item being sent or processed | 项 (counts), or the item's name | item | "3 项等待传输" |
| 缓存 / cache | Local temporary files | 临时文件 (detail); 存储空间 (row) | temporary files; Storage | |
| 局域网 / LAN | Same local network | 同一 Wi‑Fi | the same Wi‑Fi | Most users know the word Wi‑Fi |
| 配对码 / pairing code | QR code a device shows so another device can connect | 连接码 | connection code | Matches the connect flow on iPhone, Mac and Pixel (October 19); "配对" is not a user word |
| 运行记录 / 日志 / 诊断 | Activity log and its retention | 诊断信息 | Diagnostics | One term, in the footer |
| 释放空间 / free up space | Removing files that are safe elsewhere | 释放空间 | free up space | Keep; it is Android's own word |
| 原件归档 / originals archive | Exporting received files as a zip | 导出原片 | export originals | |
| 兼容转换 / compatibility conversion | Re-encoding motion photos so other apps can open them | 格式转换 | format conversion | Live Photos only: used when the still and video cannot be saved to Photos together; the video is re-encoded |
| 中转模式 / relay mode | Deletes BackupDuck's own copy once the Pixel's Photos copy is verified; Photos copies are never deleted | 存进相册后释放空间 | free up space after saving to Photos | Footer: "照片仍在 Pixel 相册里" / "Your photos stay in the Pixel's Photos" |

## Apple vocabulary alignment

These Apple labels follow the shared chosen concepts; other platforms retain
the same vocabulary when their corresponding controls are updated.

| Concept | zh-Hans | English |
| --- | --- | --- |
| Backup media categories, entry and page | 媒体类型 | Media Types |
| Album scope, entry and page | 相簿 | Albums |
| All albums / selected album count | 全部相簿 / 3 个相簿 | All Albums / 3 Albums |
| Backup records, including viewer command | 备份记录 / 在备份记录中显示 | Backup History / Show in Backup History |
| Version row / Mac update page | 版本 / 版本与更新 | Version / Version & Updates |
| Live Photo category | 实况照片 | Live Photos |
| Earlier-photo scan action (Apple) | 暂停 | Pause |
| Project source and licensing | 源代码与许可 | Source Code & Licenses |
| Bundled dependency notices, all platforms | 第三方软件 | Third-Party Software (Apple); Third-party software (Android) |

PolyForm Noncommercial is source-available; do not describe it as open source.
Apple help uses 腾出空间 for the section, 自动回收（实验） for the feature,
and 释放空间 for the action. Photos and videos together use 项; pure photos
may use 张; albums use 个. Album rows and their selected estimates include photos
and videos, so both use 项 / items. A library view that includes photos and
videos uses 项 in both its total and removable filtered-view marker. A Live
Photo failure retains the full term 实况照片 / Live Photo. Apple and Android Chinese prose, including format strings, uses full-width ？（）;
recent activity names the outcome and object rather than requests or queues.

## Pixel first-run vocabulary

The optional cleanup link is 试试自动回收（实验） / Try auto cleanup (experimental).
It opens the existing cleanup page; system Smart Storage remains the primary
first-run action.

## Voice

- Address the user directly, without 请 in labels. Keep 请 for a rare request in
  a sentence.
- Say what happens in ordinary words. A card note is one short sentence;
  procedures and settings paths belong in Help, reached by one action.
- Same-network help says 同一个 Wi‑Fi（不是访客网络） / the same Wi-Fi
  (not a guest network); do not introduce network configuration jargon.
- Say what happens next, not what the system did ("会在连上 Wi‑Fi 后继续").
- Do not claim more than the product guarantees (constitution § Copy).

## Pixel storage and source terms

| Concept | Chinese | English |
| --- | --- | --- |
| Storage section | 腾出空间 | Free up space |
| Accessibility-based optional feature | 自动回收（实验） | Auto cleanup (experimental) |
| Remove safe device copies now | 释放空间 | Free up space |
| Source and dependency licenses | 源代码与许可 | Source code & licenses |

Help on all three platforms uses 我想… / I want to… and 遇到问题时 / When
something's wrong. Connection codes use 连接码; full-quality files use 原片.
