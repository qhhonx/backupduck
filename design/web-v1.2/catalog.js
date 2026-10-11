window.WEB_CATALOG = [
  {
    "id": "login",
    "title": "访问码登录",
    "kind": "page",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "login-panel",
    "scenarios": {
      "正常": "login",
      "访问码错误": "invalid",
      "尝试过多": "locked",
      "登录中": "connecting",
      "网络失败": "login-offline"
    },
    "states": [
      "正常",
      "访问码错误",
      "尝试过多",
      "登录中",
      "网络失败"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "session",
    "title": "会话与撤销",
    "kind": "state",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "loginView",
    "scenarios": {
      "会话过期": "expired",
      "浏览器被撤销": "revoked"
    },
    "states": [
      "会话过期",
      "浏览器被撤销"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "overview",
    "title": "接收总览",
    "kind": "page",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "overview",
    "scenarios": {
      "正常": "normal",
      "加载": "loading",
      "无记录": "empty",
      "高温暂停": "thermal",
      "无法连接": "offline",
      "读数缺失": "missing"
    },
    "states": [
      "正常",
      "加载",
      "无记录",
      "高温暂停",
      "无法连接",
      "读数缺失"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "transfers",
    "title": "传输记录",
    "kind": "page",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "loadHistory",
    "scenarios": {
      "正常": "normal",
      "读取失败": "history-error",
      "加载": "loading",
      "无记录": "empty",
      "长文件名": "long",
      "日期与设备缺失": "missing"
    },
    "states": [
      "正常",
      "读取失败",
      "加载",
      "无记录",
      "长文件名",
      "日期与设备缺失"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "filters",
    "title": "搜索与筛选",
    "kind": "control",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "loadHistory / search",
    "scenarios": {
      "正常": "normal",
      "无匹配": "empty"
    },
    "states": [
      "正常",
      "无匹配"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "pagination",
    "title": "分页与刷新",
    "kind": "control",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "renderPagination",
    "scenarios": {
      "正常": "normal",
      "刷新失败": "history-error"
    },
    "states": [
      "正常",
      "刷新失败"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "detail",
    "title": "传输详情",
    "kind": "dialog",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "showDetails",
    "scenarios": {
      "正常": "normal",
      "缺失字段": "missing",
      "长文件名": "long"
    },
    "states": [
      "正常",
      "缺失字段",
      "长文件名"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "retry",
    "title": "单项重试",
    "kind": "dialog",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "showDetails / detail-retry",
    "scenarios": {
      "请求提交": "normal",
      "请求失败": "retry-error",
      "记录标识缺失": "missing-id",
      "无可重试项": "retry-zero",
      "提交中": "retry-pending"
    },
    "states": [
      "请求提交",
      "请求失败",
      "记录标识缺失",
      "无可重试项",
      "提交中"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "retry-all",
    "title": "重试全部失败项",
    "kind": "confirmation",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "retry-confirm",
    "scenarios": {
      "确认范围": "normal",
      "提交失败": "retry-error",
      "无可重试项": "retry-zero",
      "提交中": "retry-pending"
    },
    "states": [
      "确认范围",
      "提交失败",
      "无可重试项",
      "提交中"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "storage",
    "title": "手机存储",
    "kind": "page",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "overview / storage",
    "scenarios": {
      "正常": "normal",
      "读数缺失": "missing",
      "连接失败": "offline"
    },
    "states": [
      "正常",
      "读数缺失",
      "连接失败"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "settings",
    "title": "显示与接收设置",
    "kind": "page",
    "source": "crates/native/src/dashboard/app.js",
    "symbol": "setAppearance / settings",
    "scenarios": {
      "正常": "normal",
      "读数缺失": "missing",
      "连接失败": "offline"
    },
    "states": [
      "正常",
      "读数缺失",
      "连接失败"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  },
  {
    "id": "help",
    "title": "阅读帮助",
    "kind": "dialog",
    "source": "crates/native/src/dashboard/index.html",
    "symbol": "help-dialog",
    "scenarios": {
      "正常": "normal"
    },
    "states": [
      "正常"
    ],
    "native": "Synthetic interactive reference. Native and physical-device verification are separate; follow design/iteration-checklist.md."
  }
];
