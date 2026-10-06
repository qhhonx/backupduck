# Android 功能覆盖与实现进度

基准 RC.3 `8ef789c`，2026-10-03。浏览器管理常规流程已于 2026-10-03 获得用户认可；其余设计状态仍为**待用户验收**。此清单覆盖目前盘点出的应用入口、二三级流程和系统边界；不声称与所有业务分支永久一一对应。新增功能必须持续核对。

原型已设计 ≠ 原生已实现 ≠ 接口已验证 ≠ 用户验收通过。2026-10-04：56 个应用自有界面的布局、入口与状态呈现已迁移到统一原生组件；6 个系统 / 外部界面仍由系统或外部应用提供。浏览器常规流程保持用户已认可记录，其余界面待用户直接在 Pixel 验收。自动检查覆盖范围见 `validation.md`，并未验证全部 182 个业务状态。实施范围见 `implementation-plan.md`。

| ID / 页面 | 类型 | 状态数 | 功能来源 / 符号 | 原生进度 |
| --- | --- | --- | --- | --- |
| `receive` 接收 | page | 6 | [ReceiverHome.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHome.kt) / `render` | 已迁移，待 Pixel 用户验收 |
| `pairing` 连接新设备 | sheet | 3 | [PairingUI.kt](../../apps/android/app/src/main/java/app/backupduck/PairingUI.kt) / `choose / update` | 已迁移，待 Pixel 用户验收 |
| `pair-code` iPhone 配对码 | sheet | 3 | [PairingUI.kt](../../apps/android/app/src/main/java/app/backupduck/PairingUI.kt) / `code` | 已迁移，待 Pixel 用户验收 |
| `pair-scan` 扫描 Mac 配对码 | page | 4 | [PairingUI.kt](../../apps/android/app/src/main/java/app/backupduck/PairingUI.kt) / `scanning / scanned` | 已迁移，待 Pixel 用户验收 |
| `transfers` 传输 | page | 5 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `render` | 已迁移，待 Pixel 用户验收 |
| `filters` 筛选 | sheet | 1 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `showFilters` | 已迁移，待 Pixel 用户验收 |
| `filter-kind` 媒体类型 | sheet | 1 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `showFilters` | 已迁移，待 Pixel 用户验收 |
| `filter-sender` 来源设备 | sheet | 2 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `showSenders` | 已迁移，待 Pixel 用户验收 |
| `status-guide` 传输状态说明 | sheet | 1 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `showStatusGuide` | 已迁移，待 Pixel 用户验收 |
| `file-detail` 文件详情 | sheet | 6 | [HistoryPage.kt](../../apps/android/app/src/main/java/app/backupduck/HistoryPage.kt) / `showDetails` | 已迁移，待 Pixel 用户验收 |
| `storage` 存储 | page | 3 | [StoragePage.kt](../../apps/android/app/src/main/java/app/backupduck/StoragePage.kt) / `refresh` | 已迁移，待 Pixel 用户验收 |
| `storage-detail` 存储明细 | sheet | 2 | [StoragePage.kt](../../apps/android/app/src/main/java/app/backupduck/StoragePage.kt) / `showDetails` | 已迁移，待 Pixel 用户验收 |
| `storage-limits` 空间限制 | sheet | 3 | [StorageControls.kt](../../apps/android/app/src/main/java/app/backupduck/StorageControls.kt) / `showStorageControls` | 已迁移，待 Pixel 用户验收 |
| `retention` 原件保留策略 | sheet | 3 | [RetentionControls.kt](../../apps/android/app/src/main/java/app/backupduck/RetentionControls.kt) / `init` | 已迁移，待 Pixel 用户验收 |
| `relay-scope` 自动回收范围 | sheet | 3 | [RetentionControls.kt](../../apps/android/app/src/main/java/app/backupduck/RetentionControls.kt) / `save` | 已迁移，待 Pixel 用户验收 |
| `relay-history` 检查历史原件 | page | 4 | [RelayMaintenance.kt](../../apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt) / `checkHistoricalOriginals` | 已迁移，待 Pixel 用户验收 |
| `relay-preview` 历史原件检查结果 | sheet | 2 | [RelayMaintenance.kt](../../apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt) / `inspectRelay` | 已迁移，待 Pixel 用户验收 |
| `relay-reclaim` 回收已验证原件 | confirm | 3 | [RelayMaintenance.kt](../../apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt) / `reclaimRelay` | 已迁移，待 Pixel 用户验收 |
| `relay-result` 原件回收结果 | sheet | 3 | [RelayMaintenance.kt](../../apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt) / `reclaimRelay` | 已迁移，待 Pixel 用户验收 |
| `archive` 导出原件 | confirm | 1 | [OriginalArchive.kt](../../apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt) / `showArchiveIntro` | 已迁移，待 Pixel 用户验收 |
| `archive-progress` 导出与校验 | page | 5 | [OriginalArchive.kt](../../apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt) / `exportOriginals` | 已迁移，待 Pixel 用户验收 |
| `archive-result` 导出校验结果 | sheet | 2 | [OriginalArchive.kt](../../apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt) / `verify` | 已迁移，待 Pixel 用户验收 |
| `archive-reclaim` 回收已导出原件 | confirm | 3 | [OriginalArchive.kt](../../apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt) / `exportOriginals` | 已迁移，待 Pixel 用户验收 |
| `settings` 设置 | page | 1 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `settingsPage` | 已迁移，待 Pixel 用户验收 |
| `thermal` 温度保护 | sheet | 3 | [ReceivingSettingsUI.kt](../../apps/android/app/src/main/java/app/backupduck/ReceivingSettingsUI.kt) / `showThermalSettings` | 已迁移，待 Pixel 用户验收 |
| `conversion` 兼容转换 | sheet | 2 | [ReceivingSettingsUI.kt](../../apps/android/app/src/main/java/app/backupduck/ReceivingSettingsUI.kt) / `showConversionSettings` | 已迁移，待 Pixel 用户验收 |
| `browser` 浏览器管理 | page | 5 | [BrowserManagementActivity.kt](../../apps/android/app/src/main/java/app/backupduck/BrowserManagementActivity.kt) / `onCreate` | 已迁移，浏览器常规流程用户验收通过 |
| `browser-access` 访问管理页 | sheet | 3 | [DashboardAccessControls.kt](../../apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt) / `DashboardAccessUI.access` | 已迁移，浏览器常规流程用户验收通过 |
| `browser-code` 设置访问码 | sheet | 4 | [DashboardAccessControls.kt](../../apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt) / `DashboardAccessUI.code` | 已迁移，浏览器常规流程用户验收通过 |
| `browser-reset` 重置访问码 | confirm | 3 | [DashboardAccessControls.kt](../../apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt) / `DashboardAccessUI.reset` | 已迁移，浏览器常规流程用户验收通过 |
| `browser-revoke` 退出所有浏览器 | confirm | 3 | [DashboardAccessControls.kt](../../apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt) / `DashboardAccessUI.revoke` | 已迁移，浏览器常规流程用户验收通过 |
| `device-name` 设备名称 | sheet | 4 | [DeviceProfiles.kt](../../apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt) / `rename` | 已迁移，待 Pixel 用户验收 |
| `devices` 发送设备 | page | 3 | [DeviceProfiles.kt](../../apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt) / `showPeers` | 已迁移，待 Pixel 用户验收 |
| `device-detail` 发送设备详情 | sheet | 2 | [DeviceProfiles.kt](../../apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt) / `DevicePanels.showPeer` | 已迁移，待 Pixel 用户验收 |
| `device-confirm` 更改设备接收权限 | confirm | 3 | [DeviceProfiles.kt](../../apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt) / `DevicePanels.showPeer` | 已迁移，待 Pixel 用户验收 |
| `appearance` 外观 | sheet | 3 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `settingsPage` | 已迁移，待 Pixel 用户验收 |
| `language` 语言 | sheet | 3 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `settingsPage` | 已迁移，待 Pixel 用户验收 |
| `help` 使用帮助 | page | 1 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `onCreate` | 已迁移，待 Pixel 用户验收 |
| `help-connection` 连接与配对 | page | 3 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `CONNECTION` | 已迁移，待 Pixel 用户验收 |
| `help-background` 后台接收 | page | 1 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `BACKGROUND` | 已迁移，待 Pixel 用户验收 |
| `help-results` 接收与保存 | page | 1 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `RESULTS` | 已迁移，待 Pixel 用户验收 |
| `help-storage` 空间与原件 | page | 1 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `STORAGE` | 已迁移，待 Pixel 用户验收 |
| `help-recovery` 失败恢复 | page | 1 | [ReceiverHelpActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt) / `RECOVERY` | 已迁移，待 Pixel 用户验收 |
| `updates` 应用更新 | page | 9 | [AppUpdates.kt](../../apps/android/app/src/main/java/app/backupduck/AppUpdates.kt) / `UpdatesActivity` | 已迁移，待 Pixel 用户验收 |
| `diagnostics` 诊断 | page | 1 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `showDiagnostics` | 已迁移，待 Pixel 用户验收 |
| `log-limits` 日志保留 | sheet | 3 | [StorageControls.kt](../../apps/android/app/src/main/java/app/backupduck/StorageControls.kt) / `showStorageControls` | 已迁移，待 Pixel 用户验收 |
| `export-report` 导出报告 | page | 6 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `exportLogs` | 已迁移，待 Pixel 用户验收 |
| `experiments` 实验功能 | page | 1 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `onCreate` | 已迁移，待 Pixel 用户验收 |
| `cleanup` 自动释放空间 | page | 6 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `PhotosProbeActivity` | 已迁移，待 Pixel 用户验收 |
| `cleanup-disclosure` 释放空间授权说明 | confirm | 1 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `consent` | 已迁移，待 Pixel 用户验收 |
| `cleanup-bind` 绑定相册账号 | page | 4 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `bindingContent / PhotosProbeService.clean` | 已迁移，待 Pixel 用户验收 |
| `cleanup-progress` 检查释放空间 | page | 8 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `render` | 已迁移，待 Pixel 用户验收 |
| `cleanup-review` 结束结果等待 | confirm | 1 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `render` | 已迁移，待 Pixel 用户验收 |
| `photos-diagnostics` Google 相册页面检查 | page | 6 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `diagnosticsContent` | 已迁移，待 Pixel 用户验收 |
| `probe-disclosure` 页面检查授权说明 | confirm | 1 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `consent` | 已迁移，待 Pixel 用户验收 |
| `stop-receiving` 停止接收服务 | confirm | 1 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `showDiagnostics` | 已迁移，待 Pixel 用户验收 |
| `system-permission` 通知或相机权限 | system | 2 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `beginReceiving` | 系统界面 |
| `system-document` 选择导出位置 | system | 3 | [OriginalArchive.kt](../../apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt) / `export` | 系统界面 |
| `system-install` 系统安装应用 | system | 3 | [AppUpdates.kt](../../apps/android/app/src/main/java/app/backupduck/AppUpdates.kt) / `perform` | 系统界面 |
| `system-accessibility` 无障碍服务设置 | system | 2 | [ExperimentsActivity.kt](../../apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt) / `onCreate` | 系统界面 |
| `system-gallery` Google 相册 | system | 2 | [MainActivity.kt](../../apps/android/app/src/main/java/app/backupduck/MainActivity.kt) / `openPhotos` | 外部应用 |
| `system-website` 官方网站 | system | 2 | [AppUpdates.kt](../../apps/android/app/src/main/java/app/backupduck/AppUpdates.kt) / `UpdatesActivity.onCreate` | 外部浏览器 |
| `components` 组件示例 | review | 1 | [DuckDesign.kt](../../apps/android/app/src/main/java/app/backupduck/DuckDesign.kt) / `shared components` | 设计工具 |

## 纳入设计而没有静默删掉的低频功能

- 原件自动回收范围选择、历史校验预览、回收二次验证与部分保留。
- 原件 ZIP 导出、回读校验、单独确认回收；诊断日志与相册记录导出。
- 空间配额、最低可用空间、日志天数 / 数量。
- 已配对发送设备接收权限、设备改名、语言和外观。
- 应用更新检查 / 下载 / 安装权限 / 签名不兼容；开发版本与网络失败区分。
- 五类帮助主题、Google 相册页面观察、自动释放空间授权 / 绑定 / 结果核对。

## 真机与业务验收边界

1. 浏览器服务实际 Wi-Fi 启动、现有电脑登录的撤销效果、Pixel 键盘和系统字体仍单独实测；无法访问时持续显示恢复入口，不模拟地址。
2. 应用自有提示与确认框已统一迁移；访问码字段沿用已验收的始终遮蔽输入与安全窗口规则。系统权限 / 文件选择 / 安装页和外部 Google 相册仍采用真实系统界面。
3. 历史回收、导出和实验流程已采用新呈现；自动检查只覆盖安全入口、授权取消与代表配置流程。真实文件导出 / 校验 / 回收、无障碍清理及云端识别仍需要对应业务实测。
4. 历史计数统一称“接收概况”。列表继续使用 RecyclerView、按需缩略图和分页；接收、相册保存、云端结果始终分开。
5. 原型的 182 个状态是设计范围；构建、组件、代表流程与 JNI 检查通过不能自动标为全部业务状态或用户设计验收通过。
