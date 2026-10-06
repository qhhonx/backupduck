# Android 原型复刻与验收

2026-10-03。用户指出上一轮原生 UI 仅调整主题，未达到复刻要求；上一轮 Android 截图不作为通过验收的依据。此次先完成 Android，macOS / iOS / 浏览器继续等待后续改造。本轮仍未提交或发布。

## 代码对照

以 `backupduck-v1/prototype.js` 的 `receivePage`、`transfersPage`、`storagePage`、`settingsPage`、`modalContent`、`tabs` 与 `prototype.css` 为结构依据，`specification.md` / `tokens.json` 的原生字体和触控标准为尺寸约束。截图用于检查渲染后的结果。

| 原型代码 / 元素 | Android 原生对应 | 结构与交互 |
| --- | --- | --- |
| `receivePage` / `.receive-hero` | `ReceiverHome` | 淡底接收概况、图标、标题 / 说明、文字状态、全宽连接按钮；首次连接使用鸭黄背板 |
| `.pair-options` / `.pair-option` | 分组的两条连接行 | iPhone 显示码，Mac 扫描码；连接动作自动启动接收，不要求先找开关 |
| `.mini-readings` | `DuckReadings` | 三列计数与设备读数、居中数值、分隔线；真实电池温度、可用空间、电量 / 充电状态 |
| 接收页当前批次与三条记录 | `ReceiverHome` + `TransferAdapter` | 三项最近记录、全部记录入口、暂停 / 继续新接收；接收服务与相册处理继续保留 |
| `transfersPage` / `.chips` | `HistoryPage` + 原生 ChipGroup | 全部、进行中、失败、已保存四项；类型 / 来源等低频筛选放顶部更多弹层；大字体允许横向滚动 |
| `.file-row` / `.file-right` | 原生 RecyclerView / `TransferAdapter` | 两行文件信息、固定缩略图槽位、右侧文字与图标状态徽标；移除列表中的第三行与常驻底部操作按钮 |
| `.activity` / `.meter` | 原生任务条 + 底边叠层 | 52dp 基础高度，标题与解释始终有内容；真实进度覆盖底边，不占排版高度；大字体按内容统一适配 |
| `storagePage` | `StoragePage` | 标题、可用 / 总空间、占用条与分类、三条保留设置、清理说明、明细入口 |
| `settingsPage` / `.setting-group` / `.setting-row` | `DuckGroup` / `DuckSetting` | 接收设置、浏览器管理、设备与外观、帮助与关于；说明在左，开关 / 当前值在右；不使用旧的大按钮堆叠 |
| `tabs` / `.tab-icon` | Material BottomNavigationView | 接收 / 传输 / 存储 / 设置；手机、传输箭头、磁盘、齿轮图标；淡底胶囊选中态 |
| `modalContent(detail)` / `.dialog` | `DuckSheet` 文件详情 | 文件、类型、拍摄时间、来源、大小、原件与接收 / 相册阶段；失败原因与单项重试；Google 云端结果单独解释 |
| 配对与设置选择弹层 | Material BottomSheetDialog / `DuckSheet` | 底部弹层，平台返回与取消；二维码使用真实协议并禁止系统截图 |

原型 Android 页眉 48px、底栏约 62px；原生页眉保留 Material 56dp，导航 62dp，触控目标至少 48dp。原型用于桌面审阅的 10–12px 文件文字按规范提升为原生 16sp / 13sp；普通字体下行高基准 64dp，大字体允许增加。颜色来自生成变量；静态渐变使用原型的 action-background → surface，不做背景模糊。

## 动效对应

- 按压使用 Material Ripple，开关使用 MaterialSwitch，遵守系统动画缩放。
- 状态文字改变：120ms 淡入；不整体刷新、淡出列表。
- 背景遮罩 140ms 淡入；底部弹层内容：220ms、12dp 位移与淡入；退出 160ms、8dp 位移。底层导航与触摸取消由原生 BottomSheet 管理。
- 进度仅在接收端提供字节计数时显示，以 320ms 原生数值动画插值更新；不为等待或处理阶段模拟百分比。
- `ValueAnimator.areAnimatorsEnabled()` 关闭时取消自定义位移、淡入和进度插值。

## 真实数据适配

- 原型统计与温度示例不进入应用。未记录时间、未提供读数明确显示缺失。
- 存储分类使用原件、未接收完成文件与本安装的相册副本实际占用；该分类与原型示例“处理中”的数字不能直接对应。剩余已用空间由本机统计计算。
- 保存成功仅表示 Pixel 相册已保存；原件释放、接收成功与云端上传不能混用。
- 视频时长从可读的系统相册索引获取；没有可用索引时不编造。
- 手动暂停与温度 / 空间保护共同参与接收 hold；继续接收不会越过温度 / 空间保护。已接收文件继续按原流程处理。
- 原件导出、相册入口、空间配额 / 保留策略、来源设备管理、诊断导出与实验功能保留为二级入口。

## 验收证据

`ReceiverInstrumentation` 的 `design_review` 模式仅允许隔离 validation 应用与模拟器，禁止在真实 Pixel 注入样例或改配置。最终截图通过 Android `UiAutomation.takeScreenshot()` 捕获实际窗口（包含状态栏、导航栏及弹层）；合成传输记录和缩略图明确标为验收示例，不代表用户真实照片。截图目录为 `native-review/android-replica/`。测试模拟器曾出现 System UI 无响应弹窗，关闭并重新运行后才保存最终截图，不使用受弹窗覆盖的图片作为证据。

验证包含四个页面、首次 / 已启动接收、详情底部弹层、200 项虚拟化、52dp 任务区多状态几何稳定性、360dp 浅深色与 320dp 小屏。真机安装包为独立 `BackupDuck Validation`，原有 PhotoBridge 与其数据不删除。最终是否达到用户预期仍由本轮真机验收确认。

构建、现有媒体 / 温度单元检查、接收历史进行中筛选回归检查与设计变量检查通过。Pixel XL 已覆盖安装本轮验收包并启动 Activity；手机熄屏时无法核对实际画面。最大字体 / TalkBack、真机连续传输、真实配对与温度保护仍待检查，模拟器布局通过不代表这些项目完成。
