const catalog=[
  {
    "id": "receive",
    "title": "接收",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHome.kt",
    "symbol": "render",
    "states": [
      "首次使用",
      "接收中",
      "已保存",
      "高温暂停",
      "手动暂停",
      "启动失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "pairing",
    "title": "连接新设备",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/PairingUI.kt",
    "symbol": "choose / update",
    "states": [
      "正常",
      "启动中",
      "启动失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "pair-code",
    "title": "iPhone 配对码",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/PairingUI.kt",
    "symbol": "code",
    "states": [
      "有效",
      "接收不可用",
      "失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "pair-scan",
    "title": "扫描 Mac 配对码",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/PairingUI.kt",
    "symbol": "scanning / scanned",
    "states": [
      "扫描中",
      "相机权限",
      "无效码",
      "配对成功"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "transfers",
    "title": "传输",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "render",
    "states": [
      "正常",
      "空白",
      "加载中",
      "失败",
      "高温暂停"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "filters",
    "title": "筛选",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "showFilters",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "filter-kind",
    "title": "媒体类型",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "showFilters",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "filter-sender",
    "title": "来源设备",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "showSenders",
    "states": [
      "正常",
      "空白"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "status-guide",
    "title": "传输状态说明",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "showStatusGuide",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "file-detail",
    "title": "文件详情",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/HistoryPage.kt",
    "symbol": "showDetails",
    "states": [
      "已保存",
      "接收中",
      "待处理",
      "失败",
      "原件已释放",
      "时间缺失"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "storage",
    "title": "存储",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/StoragePage.kt",
    "symbol": "refresh",
    "states": [
      "正常",
      "空间不足",
      "读取失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "storage-detail",
    "title": "存储明细",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/StoragePage.kt",
    "symbol": "showDetails",
    "states": [
      "正常",
      "读取失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "storage-limits",
    "title": "空间限制",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/StorageControls.kt",
    "symbol": "showStorageControls",
    "states": [
      "正常",
      "保存中",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "retention",
    "title": "原件保留策略",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/RetentionControls.kt",
    "symbol": "init",
    "states": [
      "保留",
      "自动回收",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "relay-scope",
    "title": "自动回收范围",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/RetentionControls.kt",
    "symbol": "save",
    "states": [
      "正常",
      "保存中",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "relay-history",
    "title": "检查历史原件",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt",
    "symbol": "checkHistoricalOriginals",
    "states": [
      "检查中",
      "等待降温",
      "检查失败",
      "已取消"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "relay-preview",
    "title": "历史原件检查结果",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt",
    "symbol": "inspectRelay",
    "states": [
      "有可回收项",
      "无可回收项"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "relay-reclaim",
    "title": "回收已验证原件",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt",
    "symbol": "reclaimRelay",
    "states": [
      "确认",
      "回收中",
      "回收失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "relay-result",
    "title": "原件回收结果",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/RelayMaintenance.kt",
    "symbol": "reclaimRelay",
    "states": [
      "完成",
      "部分保留",
      "已取消"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "archive",
    "title": "导出原件",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt",
    "symbol": "showArchiveIntro",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "archive-progress",
    "title": "导出与校验",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt",
    "symbol": "exportOriginals",
    "states": [
      "导出中",
      "校验中",
      "没有原件",
      "失败",
      "已取消"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "archive-result",
    "title": "导出校验结果",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt",
    "symbol": "verify",
    "states": [
      "校验通过",
      "校验失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "archive-reclaim",
    "title": "回收已导出原件",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt",
    "symbol": "exportOriginals",
    "states": [
      "确认",
      "回收中",
      "失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "settings",
    "title": "设置",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "settingsPage",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "thermal",
    "title": "温度保护",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceivingSettingsUI.kt",
    "symbol": "showThermalSettings",
    "states": [
      "正常",
      "保护关闭",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "conversion",
    "title": "兼容转换",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceivingSettingsUI.kt",
    "symbol": "showConversionSettings",
    "states": [
      "关闭",
      "开启"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "browser",
    "title": "浏览器管理",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/BrowserManagementActivity.kt",
    "symbol": "onCreate",
    "states": [
      "已开启",
      "未开启",
      "启动中",
      "启动失败",
      "接收未启动"
    ],
    "native": "已迁移，浏览器常规流程用户验收通过"
  },
  {
    "id": "browser-access",
    "title": "访问管理页",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt",
    "symbol": "DashboardAccessUI.access",
    "states": [
      "可访问",
      "接收未启动",
      "地址不可用"
    ],
    "native": "已迁移，浏览器常规流程用户验收通过"
  },
  {
    "id": "browser-code",
    "title": "设置访问码",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt",
    "symbol": "DashboardAccessUI.code",
    "states": [
      "正常",
      "输入错误",
      "保存中",
      "保存失败"
    ],
    "native": "已迁移，浏览器常规流程用户验收通过"
  },
  {
    "id": "browser-reset",
    "title": "重置访问码",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt",
    "symbol": "DashboardAccessUI.reset",
    "states": [
      "确认",
      "处理中",
      "失败"
    ],
    "native": "已迁移，浏览器常规流程用户验收通过"
  },
  {
    "id": "browser-revoke",
    "title": "退出所有浏览器",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/DashboardAccessControls.kt",
    "symbol": "DashboardAccessUI.revoke",
    "states": [
      "确认",
      "处理中",
      "失败"
    ],
    "native": "已迁移，浏览器常规流程用户验收通过"
  },
  {
    "id": "device-name",
    "title": "设备名称",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt",
    "symbol": "rename",
    "states": [
      "正常",
      "名称无效",
      "保存中",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "devices",
    "title": "发送设备",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt",
    "symbol": "showPeers",
    "states": [
      "正常",
      "空白",
      "读取失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "device-detail",
    "title": "发送设备详情",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt",
    "symbol": "DevicePanels.showPeer",
    "states": [
      "允许接收",
      "已禁用"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "device-confirm",
    "title": "更改设备接收权限",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/DeviceProfiles.kt",
    "symbol": "DevicePanels.showPeer",
    "states": [
      "确认",
      "处理中",
      "失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "appearance",
    "title": "外观",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "settingsPage",
    "states": [
      "跟随系统",
      "浅色",
      "深色"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "language",
    "title": "语言",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "settingsPage",
    "states": [
      "跟随系统",
      "简体中文",
      "English"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help",
    "title": "使用帮助",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "onCreate",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help-connection",
    "title": "连接与配对",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "CONNECTION",
    "states": [
      "有地址",
      "未启动",
      "读取失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help-background",
    "title": "后台接收",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "BACKGROUND",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help-results",
    "title": "接收与保存",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "RESULTS",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help-storage",
    "title": "空间与原件",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "STORAGE",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "help-recovery",
    "title": "失败恢复",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ReceiverHelpActivity.kt",
    "symbol": "RECOVERY",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "updates",
    "title": "应用更新",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/AppUpdates.kt",
    "symbol": "UpdatesActivity",
    "states": [
      "检查中",
      "最新版",
      "可更新",
      "检查失败",
      "下载中",
      "下载失败",
      "安装权限",
      "签名不兼容",
      "开发版本"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "diagnostics",
    "title": "诊断",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "showDiagnostics",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "log-limits",
    "title": "日志保留",
    "kind": "sheet",
    "source": "apps/android/app/src/main/java/app/backupduck/StorageControls.kt",
    "symbol": "showStorageControls",
    "states": [
      "正常",
      "保存中",
      "保存失败"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "export-report",
    "title": "导出报告",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "exportLogs",
    "states": [
      "日志",
      "相册记录",
      "检查报告",
      "导出中",
      "导出失败",
      "导出成功"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "experiments",
    "title": "实验功能",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "onCreate",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "cleanup",
    "title": "自动释放空间",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "PhotosProbeActivity",
    "states": [
      "未授权",
      "未绑定",
      "就绪",
      "运行中",
      "结果待核对",
      "账号改变"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "cleanup-disclosure",
    "title": "释放空间授权说明",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "consent",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "cleanup-bind",
    "title": "绑定相册账号",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "bindingContent / PhotosProbeService.clean",
    "states": [
      "检查中",
      "已绑定",
      "无法识别",
      "需要解锁"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "cleanup-progress",
    "title": "检查释放空间",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "render",
    "states": [
      "运行中",
      "等待相册",
      "已完成",
      "没有可释放文件",
      "页面无法识别",
      "需要解锁",
      "超时",
      "已停止"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "cleanup-review",
    "title": "结束结果等待",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "render",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "photos-diagnostics",
    "title": "Google 相册页面检查",
    "kind": "page",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "diagnosticsContent",
    "states": [
      "未授权",
      "就绪",
      "检查中",
      "已完成",
      "超时",
      "中断"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "probe-disclosure",
    "title": "页面检查授权说明",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "consent",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "stop-receiving",
    "title": "停止接收服务",
    "kind": "confirm",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "showDiagnostics",
    "states": [
      "正常"
    ],
    "native": "已迁移，待 Pixel 用户验收"
  },
  {
    "id": "system-permission",
    "title": "通知或相机权限",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "beginReceiving",
    "states": [
      "允许",
      "拒绝"
    ],
    "native": "系统界面"
  },
  {
    "id": "system-document",
    "title": "选择导出位置",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/OriginalArchive.kt",
    "symbol": "export",
    "states": [
      "选择",
      "取消",
      "失败"
    ],
    "native": "系统界面"
  },
  {
    "id": "system-install",
    "title": "系统安装应用",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/AppUpdates.kt",
    "symbol": "perform",
    "states": [
      "允许",
      "取消",
      "失败"
    ],
    "native": "系统界面"
  },
  {
    "id": "system-accessibility",
    "title": "无障碍服务设置",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/ExperimentsActivity.kt",
    "symbol": "onCreate",
    "states": [
      "开启",
      "返回未授权"
    ],
    "native": "系统界面"
  },
  {
    "id": "system-gallery",
    "title": "Google 相册",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/MainActivity.kt",
    "symbol": "openPhotos",
    "states": [
      "已打开",
      "未安装"
    ],
    "native": "外部应用"
  },
  {
    "id": "system-website",
    "title": "官方网站",
    "kind": "system",
    "source": "apps/android/app/src/main/java/app/backupduck/AppUpdates.kt",
    "symbol": "UpdatesActivity.onCreate",
    "states": [
      "已打开",
      "无法打开"
    ],
    "native": "外部浏览器"
  },
  {
    "id": "components",
    "title": "组件示例",
    "kind": "review",
    "source": "apps/android/app/src/main/java/app/backupduck/DuckDesign.kt",
    "symbol": "shared components",
    "states": [
      "正常"
    ],
    "native": "设计工具"
  }
];
