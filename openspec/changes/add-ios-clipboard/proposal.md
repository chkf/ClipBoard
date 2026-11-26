## Why

新的复制操作会替换系统剪贴板的当前内容。Clipboard 让个人用户在主 App 或键盘活动时自动保存可读取的文本和图片，随后在支持第三方键盘的 App 中直接复用。

## What Changes

- 提供 iOS 26+ 原生主 App，用于浏览、复制、预览及删除本地历史，配置保留期限和键盘行为。
- 提供 Clipboard 键盘，用于插入完整文本、复制完整图片以及切换键盘。
- 两个入口共享同一份历史和复制事件状态。同一次复制只处理一次，再次复制相同内容会更新原记录的排序与保留期限。
- 以可侧载的 IPA 交付主 App 和键盘扩展，离线完成全部核心操作。

## Capabilities

### New Capabilities

- `clipboard-capture` — [活动时自动收集、识别复制事件与处理权限](specs/clipboard-capture/spec.md)
- `shared-history` — [本地历史的去重、排序、保留期限、清理与跨进程一致性](specs/shared-history/spec.md)
- `clipboard-app` — [原生列表、完整预览、重新复制、删除、首次使用指引和设置](specs/clipboard-app/spec.md)
- `clipboard-keyboard` — [扩展启用、历史浏览、完整文本插入、图片复制与键盘切换](specs/clipboard-keyboard/spec.md)

### Modified Capabilities

无。

## Impact

主 App 和 Keyboard Extension 通过 Shared Core 及 App Groups 共享数据。IPA 的签名与构建配置需要覆盖两个目标及共享权限。SQLite 和共享容器文件是 PRD 推荐的存储方案，具体选择在技术设计阶段确定。

完整范围、排除项及 17 项验收标准见[产品需求报告](../../../docs/PRD.md)。
