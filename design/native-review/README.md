# 四端实际界面验收图 · 2026-10-02

这些图来自当前工作区中的实际界面代码，不是设计原型；应用尚未发布，代码尚未提交。全部使用隔离测试数据或未配对的空应用，没有私人照片、账号或配对凭据。

打开 `index.html` 可按端、浅深色看图。每张可点开原图。

| 目录 | 捕获方式 / 数据 | 能证明 / 不能证明 |
| --- | --- | --- |
| `browser/` | Playwright 打开实际管理页文件，隔离合成 API；67 条项目 | 实际 DOM、页面、筛选、分页、详情和浅深色；不能证明真实 Pixel / 云端结果 |
| `android/` | 隔离模拟器启动实际 validation 应用，绘制原生 View 树；12 条合成传输项 | 实际 Material / RecyclerView 布局、四页和浅深色；系统状态栏不在图中。此次模拟器宽度约 548 dp，不等于旧 Pixel 的 320 dp 真机验收 |
| `macos/` | 实际 SwiftUI 组件在 NSHostingView 中离屏渲染；合成状态 | 正文、失败详情与浅深色；系统控件非活动色与侧边栏材质不能据此验收，因此不收录材质捕获异常的窗口图 |
| `ios/` | XCTest 启动独立 iOS 18.1 模拟器中的实际应用并截图 | 实际导航、系统控件与主要页面。图库无私人数据；连续传输和真实照片仍需真机验收 |

## 可复现检查

- `python3 scripts/export-design-tokens.py --check`
- `tests/mac_layout.sh --transfer-layout-only`：实际传输 / 准备行和底部任务区多状态高度检查。
- `tests/mac_layout.sh --design-review`：隔离 store 下的实际 macOS 组件图。
- `BACKUPDUCK_PLAYWRIGHT=/本机路径/playwright node tests/dashboard_ui.cjs`：实际浏览器 UI + 本地测试 API。
- Android `ReceiverInstrumentation` 的 `design_review` 模式：仅可在 `.validation` 应用执行；`dark=true/false`。
- iOS `BackupDuckUI` scheme / `SettingsTests.testDesignReviewScreens`：使用独立模拟器，测试应用需要正确的 Simulator.entitlements。unsigned 构建会产生 Keychain 错误，不能把这类测试环境错误当正常产品状态。

业务与设计对照、自动检查和待真机项目见上一级 `native-implementation.md`。截图检查之后调整了 iOS 列表说明与筛选密度，验收目录只保留最终截图。
