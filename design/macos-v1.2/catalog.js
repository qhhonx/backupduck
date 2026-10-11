const catalog = [
  {
    "id": "library",
    "title": "系统图库",
    "kind": "page",
    "states": [
      "正常",
      "读取中",
      "权限未决定",
      "权限拒绝",
      "无照片",
      "筛选为空"
    ],
    "source": "apps/macos/BackupDuck/BackupDuckMacApp.swift",
    "symbol": "MacWorkspace.libraryPage",
    "owner": "library",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "library-filter",
    "title": "图库类型筛选",
    "kind": "popover",
    "states": [
      "全部",
      "照片",
      "实况",
      "视频",
      "连拍"
    ],
    "source": "apps/apple/Shared/PhotoLibraryModel.swift",
    "symbol": "LibraryFilter / 图库类型",
    "owner": "library",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "selected-backup",
    "title": "备份所选",
    "kind": "sheet",
    "states": [
      "普通备份",
      "强制重传",
      "提交中",
      "提交失败"
    ],
    "source": "apps/apple/Shared/DuckComponents.swift",
    "symbol": "DuckSelectedBackup(async Bool) / MacWorkspace.backupSelection",
    "owner": "library",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "photo-detail",
    "title": "图库项目详情",
    "kind": "sheet",
    "states": [
      "照片",
      "实况",
      "视频",
      "连拍",
      "日期缺失"
    ],
    "source": "apps/macos/BackupDuck/BackupDuckMacApp.swift",
    "symbol": "library.show_details / DuckPhotoDetail",
    "owner": "library",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folders",
    "title": "文件夹来源",
    "kind": "page",
    "states": [
      "正常",
      "空来源",
      "扫描中",
      "离线",
      "读取失败",
      "全局暂停"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderSourcesPage",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-menu",
    "title": "来源更多操作",
    "kind": "popover",
    "states": [
      "正常"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderSourceCard.Menu",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-add",
    "title": "添加文件夹",
    "kind": "sheet",
    "states": [
      "正常",
      "规则展开",
      "保存中",
      "保存失败",
      "来源重叠"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "AddFolderSheet",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-rules",
    "title": "备份规则",
    "kind": "sheet",
    "states": [
      "正常",
      "高级语法",
      "保存中",
      "规则无效",
      "保存失败"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderRulesSheet",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-remove",
    "title": "移除来源",
    "kind": "confirm",
    "states": [
      "正常",
      "处理中",
      "失败"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderRemoveSheet / FolderSources.remove",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-help",
    "title": "文件夹说明",
    "kind": "sheet",
    "states": [
      "纯阅读"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderSourcesPage.showHelp",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-detail",
    "title": "来源文件",
    "kind": "page",
    "states": [
      "平铺",
      "文件夹树",
      "加载中",
      "无文件",
      "加载失败",
      "离线",
      "等待配对"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderSourceDetail",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-sort",
    "title": "文件排序",
    "kind": "popover",
    "states": [
      "平铺排序",
      "目录排序"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderSortControl",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-file-detail",
    "title": "文件详情",
    "kind": "sheet",
    "states": [
      "未排队",
      "进行中",
      "已接收",
      "时间缺失",
      "路径很长"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderFileRow / FolderFileDetail",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-issues",
    "title": "未备份文件",
    "kind": "page",
    "states": [
      "有问题",
      "无问题",
      "重试等待",
      "重试失败"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderIssuesPage",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-issue-detail",
    "title": "未备份文件详情",
    "kind": "sheet",
    "states": [
      "正常",
      "重试中",
      "已请求重试",
      "重试失败",
      "原因缺失"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderIssueDetail",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "folder-ignore",
    "title": "忽略此版本",
    "kind": "confirm",
    "states": [
      "正常",
      "处理中",
      "失败"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "FolderIssueDetail.ignore",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "backup",
    "title": "备份概览",
    "kind": "page",
    "states": [
      "未配对",
      "加载中",
      "等待发送",
      "正在传输",
      "手动暂停",
      "等待连接",
      "高温暂停",
      "相册处理失败",
      "已保存",
      "等待相册处理"
    ],
    "source": "apps/macos/BackupDuck/MacBackupPage.swift",
    "symbol": "MacBackupPage",
    "owner": "backup",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfers",
    "title": "传输任务",
    "kind": "page",
    "states": [
      "正常",
      "加载中",
      "无任务",
      "筛选为空",
      "读取失败",
      "正在传输",
      "等待调度",
      "等待确认"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "TransferList",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfer-filter",
    "title": "传输筛选",
    "kind": "popover",
    "states": [
      "全部",
      "进行中",
      "失败",
      "已保存",
      "准备原件",
      "历史扫描"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "TransferList.Picker",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfer-source",
    "title": "来源筛选",
    "kind": "popover",
    "states": [
      "全部",
      "系统图库",
      "文件夹"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "TransferList.source",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfer-sort",
    "title": "任务排序",
    "kind": "popover",
    "states": [
      "加入时间",
      "拍摄时间",
      "从新到旧",
      "从旧到新"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "TransferList.sort",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfer-detail",
    "title": "任务详情",
    "kind": "sheet",
    "states": [
      "等待发送",
      "传输中",
      "等待确认",
      "已接收待处理",
      "已保存",
      "发送失败",
      "相册失败",
      "重试中",
      "请求失败",
      "日期缺失"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "DuckTransferDetail",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "status-guide",
    "title": "状态说明",
    "kind": "sheet",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "TransferStatusGuide",
    "owner": "transfers",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "receiver",
    "title": "接收设备",
    "kind": "page",
    "states": [
      "未配对",
      "已配对",
      "检查中",
      "连接正常",
      "连接不可用",
      "高温暂停"
    ],
    "source": "apps/macos/BackupDuck/BackupDuckMacApp.swift",
    "symbol": "ReceiverPage",
    "owner": "receiver",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "pair-code",
    "title": "Mac 配对码",
    "kind": "sheet",
    "states": [
      "生成中",
      "有效",
      "过期",
      "没有网络",
      "生成失败",
      "配对中",
      "配对成功"
    ],
    "source": "apps/macos/BackupDuck/BackupDuckMacApp.swift",
    "symbol": "MacPairingSheet / DesktopPairingModel",
    "owner": "receiver",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "connection-status",
    "title": "连接状态详情",
    "kind": "sheet",
    "states": [
      "检查中",
      "在线",
      "离线",
      "网络权限",
      "无远端读数"
    ],
    "source": "apps/apple/Shared/TransferViews.swift",
    "symbol": "ReceiverStatusIndicator",
    "owner": "receiver",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "settings",
    "title": "设置",
    "kind": "page",
    "states": [
      "正常",
      "未配对",
      "配置读取失败",
      "保存中"
    ],
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "MacPreferences",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "history-settings",
    "title": "图库备份设置",
    "kind": "sheet",
    "states": [
      "未开始",
      "扫描中",
      "已暂停",
      "已扫描",
      "快照失效",
      "操作失败",
      "操作中"
    ],
    "source": "apps/apple/Shared/HistoricalImport.swift",
    "symbol": "MacLibraryBackupPreferences",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "concurrency",
    "title": "并发传输",
    "kind": "section",
    "states": [
      "正常",
      "保存中",
      "保存失败"
    ],
    "source": "apps/apple/Shared/TransferConcurrencySettings.swift",
    "symbol": "TransferConcurrencySettings / 设置内即时保存",
    "owner": "backup",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "cache",
    "title": "本地缓存",
    "kind": "section",
    "states": [
      "正常",
      "读取中",
      "读取失败",
      "保存中",
      "保存失败",
      "空间不足",
      "缓存为空"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "StoragePreferences(scope: cache) / 设置内即时保存",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "cache-reclaim",
    "title": "检查并释放缓存",
    "kind": "section",
    "states": [
      "检查中",
      "已释放",
      "没有可释放项",
      "部分保留",
      "检查失败"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "StoragePreferences inline reclaim / BackupModel.reclaimCache",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "diagnostics",
    "title": "诊断",
    "kind": "page",
    "states": [
      "正常",
      "读取中",
      "读取失败"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "ActivityLogView",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "log-detail",
    "title": "运行记录详情",
    "kind": "sheet",
    "states": [
      "正常",
      "长上下文",
      "缺少时间"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "ActivityLogDetail",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "log-retention",
    "title": "日志保留",
    "kind": "section",
    "states": [
      "正常",
      "保存中",
      "保存失败"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "StoragePreferences(scope: logs) / 设置内即时保存",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "diagnostics-export",
    "title": "导出诊断报告",
    "kind": "sheet",
    "states": [
      "正常",
      "导出中",
      "导出成功",
      "导出失败",
      "已取消"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "ActivityLogExportSheet / ActivityLogExporter",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "device-name",
    "title": "设备名称",
    "kind": "sheet",
    "states": [
      "正常",
      "名称无效",
      "保存中",
      "保存失败",
      "保存成功"
    ],
    "source": "apps/apple/Shared/DeviceIdentity.swift",
    "symbol": "DeviceNameEditor",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "appearance",
    "title": "外观",
    "kind": "popover",
    "states": [
      "跟随系统",
      "浅色",
      "深色"
    ],
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "duckAppearance",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "language",
    "title": "语言",
    "kind": "section",
    "states": [
      "系统语言",
      "打开失败"
    ],
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "NSWorkspace.open System Settings",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "updates",
    "title": "应用更新",
    "kind": "sheet",
    "states": [
      "正常",
      "自动检查关闭",
      "检查中",
      "最新版",
      "可更新",
      "检查失败",
      "退出后安装"
    ],
    "source": "apps/macos/BackupDuck/AppUpdater.swift",
    "symbol": "UpdateSettings / Sparkle",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help",
    "title": "使用帮助",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "BackupHelp",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-connection",
    "title": "连接与配对",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "help_start_body",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-library",
    "title": "图库备份",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "mac_help_library",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-folders",
    "title": "文件夹与规则",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "mac_help_folders",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-background",
    "title": "后台与暂停",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "mac_running_note / mac_global_pause_note",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-results",
    "title": "接收、保存与云端",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "mac_help_receipt",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-recovery",
    "title": "失败恢复与诊断",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "help_recover_body / help_support_body",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help-permissions",
    "title": "权限与空间",
    "kind": "page",
    "states": [
      "纯阅读"
    ],
    "source": "apps/apple/Shared/BackupHelp.swift",
    "symbol": "mac_help_permissions / help_space_body",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "menu-bar",
    "title": "菜单栏",
    "kind": "popover",
    "states": [
      "未配对",
      "正在传输",
      "等待连接",
      "手动暂停",
      "相册失败"
    ],
    "source": "apps/macos/BackupDuck/MacStatusMenu.swift",
    "symbol": "MacStatusMenu",
    "owner": "backup",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-folder",
    "title": "系统文件夹选择器",
    "kind": "system",
    "states": [
      "已选择",
      "取消",
      "不可访问"
    ],
    "source": "apps/macos/BackupDuck/FolderSourcesPage.swift",
    "symbol": "NSOpenPanel",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-photos",
    "title": "系统照片权限",
    "kind": "system",
    "states": [
      "允许访问",
      "拒绝",
      "受限制"
    ],
    "source": "apps/apple/Shared/PhotoLibraryModel.swift",
    "symbol": "PHPhotoLibrary.requestAuthorization",
    "owner": "library",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-save",
    "title": "系统分享 / 保存",
    "kind": "system",
    "states": [
      "选择位置",
      "取消",
      "写入失败"
    ],
    "source": "apps/apple/Shared/StorageModel.swift",
    "symbol": "ActivityLogExportSheet.ShareLink",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-language",
    "title": "系统语言设置",
    "kind": "system",
    "states": [
      "打开成功",
      "打开失败"
    ],
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "NSWorkspace.open",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-update",
    "title": "Sparkle 更新窗口",
    "kind": "system",
    "states": [
      "检查",
      "下载",
      "验证失败",
      "安装与重启"
    ],
    "source": "apps/macos/BackupDuck/AppUpdater.swift",
    "symbol": "SPUStandardUpdaterController",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-reveal",
    "title": "Finder 显示原文件",
    "kind": "system",
    "states": [
      "已定位",
      "来源离线"
    ],
    "source": "apps/macos/BackupDuck/FolderSources.swift",
    "symbol": "NSWorkspace.activateFileViewerSelecting",
    "owner": "folders",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "system-website",
    "title": "官方网站",
    "kind": "system",
    "states": [
      "进入网站",
      "返回应用"
    ],
    "source": "apps/macos/BackupDuck/AppUpdater.swift",
    "symbol": "Link official_website",
    "owner": "settings",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "about",
    "title": "关于备份鸭",
    "kind": "page",
    "owner": "settings",
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "MacSettingsRoute.about",
    "states": [
      "正常"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "list-display",
    "title": "列表显示",
    "kind": "page",
    "states": [
      "正常"
    ],
    "owner": "settings",
    "source": "apps/macos/BackupDuck/MacPreferences.swift",
    "symbol": "list display preferences",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "backup-settings",
    "title": "备份设置",
    "kind": "sheet",
    "states": [
      "正常"
    ],
    "owner": "backup",
    "source": "apps/macos/BackupDuck/MacBackupPage.swift",
    "symbol": "global backup preferences",
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  }
];
