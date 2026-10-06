# UI 改版分支交接

2026-10-06。分支：`ui-redesign`，远端仓库：`qhhonx/backupduck`。
本分支保存此前在 Mac mini 上未提交的完整改版，供 MacBook Air 接续；不是正式发布，也不是用户已验收版本。

## 当前成果与下一步

| 平台 | 本分支包含 | 当前状态 |
| --- | --- | --- |
| Android | v1.2 完整流程原型、56 个自有界面的原生迁移、共享组件与代表流程检查 | 浏览器管理常规流程已认可；其余等待用户在另一台 Pixel 上验收 |
| iOS / macOS | v1.1 原型、共享颜色与组件、此前页面与状态调整 | 用户认为上一轮没有充分还原原型，需在 Android 方法稳定后继续复刻 |
| 接收端浏览器 | v1.1 原型、四页布局、全库搜索、分页及单项重试 | 包含此前实现与隔离检查记录；未宣称完成新的全面验收 |
| 共享业务 | 任务阶段筛选、历史查找与失败计数、单项相册处理重试 | 支撑界面所需；接收、Pixel 相册保存、Google 相册云端备份仍是独立事实 |

下一步先完成 Android 真机验收与问题修复，再推进其他平台。不要同时铺开四端，不要根据旧截图重做已有成果。直接读原型代码，以功能入口、页面结构、动作层级、状态和反馈为契约。

## 在 MacBook Air 接续

先定位现有仓库，读取 `AGENTS.md`，确认没有会被覆盖的本地工作。若已有修改，先独立保存；不要使用强制重置、强制切换或清空操作。

先看 `git config --get-all remote.origin.fetch`。如果只同步 `main`，需要额外登记新分支，否则普通 fetch 不会发现它（Mac mini 的原配置就是如此）：

```sh
git config --add remote.origin.fetch '+refs/heads/ui-redesign:refs/remotes/origin/ui-redesign'
```

已有 `+refs/heads/*:refs/remotes/origin/*` 或上面的 UI 分支规则时，跳过这一步。

```sh
git fetch origin
git switch --track origin/ui-redesign
```

如果本地已经有 `ui-redesign`，切换该分支后使用 `git pull --ff-only`。不要直接把分支合进 `main`。先检查远端最新提交，并阅读以下资料：

- [设计入口](README.md)、[跨端 v1.1 规范](backupduck-v1/specification.md)、[动效指南](backupduck-v1/motion.md)。
- [Android v1.2 原型](android-v1.2/index.html)、[组件契约](android-v1.2/specification.md)、[覆盖清单](android-v1.2/coverage.md)。
- [还原与验收方法](android-v1.2/native-acceptance.md)、[验证记录](android-v1.2/validation.md)、[实施范围](android-v1.2/implementation-plan.md)。
- [此前跨端实施边界](native-implementation.md)。

历史文档中的“未提交”描述的是当时状态；本文件记录本次提交交接，不回写历史为用户已验收。设计源文件在仓库内，托管原型只是便于体验的副本。可查看 Linear 相关记录补充进度；没有访问工具时，不虚构任务状态。

## 验证包与设备

2026-10-04 的 `BackupDuck Validation`：

- 包名 `app.backupduck.validation`，版本 `0.2.0-rc.3-dev` / 46，与正式版并存、数据独立。
- SHA-256：`3173c800cfd0d4bc4afe281856448353eb0900d4a6dee68d24b5cad58b4a1d3e`。
- 验证包接收端口 `48484`；正式包仍为 `8484`，避免两者同时运行时冲突。
- 已在 Mac mini 旁 Pixel XL 安装；用户尚未完成本轮整体验收，另一台 Pixel 需要独立安装、授权及重新配对。

APK、编译输出、设备数据和签名密钥不纳入 Git。Air 需要用仓库构建脚本准备原生库与验证包，不能假设忽略的 `jniLibs` 和 `build` 产物会随分支传过去。跨机器重新编译的调试包可能使用不同签名；若已有验证包不能覆盖安装，先核对签名和数据保留方案，不能直接卸载清空。

设置好 Java / Android SDK / NDK 及 Rust Android target 后，可用 `ORG_GRADLE_PROJECT_validationApp=true ./scripts/build-android.sh` 构建独立验证包。核对输出包名为 `app.backupduck.validation` 后再安装，不能直接把默认构建当作验证包覆盖正式应用。

在操作设备前确认目标身份。只在隔离模拟器运行合成业务检查，不向真实 Pixel 安装测试 APK 或注入测试历史。用户直接在 Pixel 验收，不用截图集合作为交付方式；内部仍需检查实际原生窗口。

## 已有证据与限制

2026-10-04 的自动检查记录：Android 原型 63 项契约 / 182 个模拟状态；原生 411dp 标准字体、320dp 两倍字体，均覆盖浅深色、共享组件与代表流程，另有中文大字体深色组件检查。具体范围见验证记录，不能据此宣称全部 182 个业务状态均实测通过。

旧 Pixel 的键盘、TalkBack、连续大批量接收、文件导出 / 校验 / 回收、系统授权返回、无障碍实验及 Google 相册云端结果仍需对应验证。本次分支提交不触发正式应用发布，不修改上述验收结论。

本次交接前重新通过：Rust 四个相关 crate 的测试（78 通过、1 项按既有条件忽略）、格式检查、设计颜色生成核对、脚本语法、Android 原型契约及浏览器管理四页 / 浅深色 / 搜索 / 分页 / 单项重试检查。首次 Rust 检查受沙箱监听端口限制，允许隔离测试的本机端口后重跑通过；没有修改测试断言。Android 原生矩阵沿用上面的 2026-10-04 记录，本次没有重装设备或扩大其通过范围。

## 后续协作与分支清理

用户已授权把当前改版提交并推送至此分支，以便跨电脑接续；没有授权合并 `main` 或发布正式版本。后续按用户当次授权执行提交与发布，不擅自扩展到正式渠道。不改变电脑锁屏、电源设置或保持唤醒。

完成用户验收、必要检查并合并后，可删除远端及各电脑的本地 `ui-redesign` 分支。删分支只删除分支引用，不会删除已合入主线的代码和提交历史；如果放弃改版且未合并，应先保存需要保留的成果，不能把删除当作代码历史清除。
