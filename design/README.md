# 备份鸭设计交付

2026-10-06：此前未提交的改版整理到 `ui-redesign` 分支，供 MacBook Air 接续；当前状态、验收边界与操作方式见 [分支交接](ui-redesign-handoff.md)。尚未合入主线或正式发布，下方历史记录保留当时状态。

当前基准为 **v1.1（2026-10-02）**。`backupduck-v1/` 表示设计的主版本；小版本在规范与变量中记录，不重复复制整个目录。

## 正式保存位置

- [交互原型](backupduck-v1/index.html)：四端页面、状态与关键操作。
- [设计标准](backupduck-v1/specification.md)：颜色、排版、平台材质、状态语义与原生验收要求。
- [设计变量](backupduck-v1/tokens.json)：浅深色、间距、字号、密度与动效。
- [动效指南](backupduck-v1/motion.md)：反馈、任务区稳定性与辅助功能回退。
- [30 张视觉稿](backupduck-v1/previews/index.html)：各端页面及材质、鸭黄实例。
- [验证记录](backupduck-v1/validation.md)：网页原型验证结果及原生验收边界。

这些源文件作为项目内的设计基准纳入 Git；托管预览用于体验，不取代这里的源文件。预览的访问权限与应用发布独立，不在源文件中保存私人预览地址或访问凭据。

## 原生落地方式

页面结构、动作层级、状态含义、品牌色与密度按此基准实施；导航、选择器、弹层、材质与辅助功能由平台原生组件提供。网页 CSS 不是 Liquid Glass 的原生实现，不能将网页套进 WebView 来替代应用。

图库与长列表复用已有原生列表、缩略图缓存和分页。真实数据没有提供的温度、空间、日期或云端结果必须显示缺失或等待状态，不能用原型的示例值补齐。

| 设计范围 | 现有实现位置 |
| --- | --- |
| Apple 共用状态与传输 | `apps/apple/Shared/TransferViews.swift`、`BackupModel.swift` |
| macOS 页面与导航 | `apps/macos/BackupDuck/` |
| iOS 页面与导航 | `apps/ios/BackupDuck/` |
| Android 页面、列表与主题 | `apps/android/app/src/main/` |
| 接收端浏览器管理 | `crates/native/src/dashboard/` |

在真机和浏览器上对照视觉稿验收：主要页面与异常状态、浅深色、旧系统、小屏、大字体、减少透明度 / 动效、键盘 / 屏幕阅读器，以及列表滚动、接收和失败恢复。网页检查不等于应用实现已通过这些验收。

## 当前原生验收

[实现与保留功能对照](native-implementation.md) · [四端实际界面图集](native-review/index.html) · [截图捕获与验收边界](native-review/README.md)。当前原生改版在工作区等待用户验收，未提交、未发布。

2026-10-03：上一轮原生界面未通过用户设计验收；现先进行 [Android 原型复刻](android-replica.md)，以原型代码逐项落实结构和交互。

## Android 完整流程草案

2026-10-03：用户反馈二三级界面、弹窗与反馈缺少统一标准，按 RC.3 功能继续盘点。新的 [Android v1.2 原型](android-v1.2/index.html)、[实施标准](android-v1.2/specification.md)、[覆盖清单](android-v1.2/coverage.md)、[验证记录](android-v1.2/validation.md) 单独保存，沿用 v1.1 视觉方向；未替代已批准的跨端基准。先验证浏览器管理完整流程，再按同一方法推进其余 Android 页面。

[原型还原实施与验收流程](android-v1.2/native-acceptance.md) 规定交付顺序、组件契约、状态转换、实际窗口反馈及真机证据边界；独立模拟器检查脚本为 `scripts/verify-android-ui.py`。

2026-10-04：Android v1.2 的全部自有页面、弹层与确认框已迁移到统一原生组件，覆盖及验证边界保存在上述清单。内部继续做实际窗口检查；用户直接在 Pixel 上验收独立 `BackupDuck Validation` 应用，不使用截图集合替代体验。其余平台暂不扩展，代码保持未提交。
