# Clipboard

iOS 26 及以上版本的本地剪贴板键盘。切到 Clipboard 时，键盘会保存系统允许读取的当前文本或图片。主 App 提供启用说明、试用输入框和键盘设置，首页打开时保持键盘收起。

## 安装

1. 在发布页下载 `Clipboard-版本-local.ipa`，用全能签重签整个包并保留键盘扩展。用自己的 Apple ID 安装时，也可以在 SideStore 导入 IPA 并选择保留扩展。[下载 Clipboard](https://github.com/chkf/ClipBoard/releases/latest) · [SideStore 安装指南](https://docs.sidestore.io/)
2. 在 iPhone「设置」→「通用」→「键盘」→「键盘」中添加 Clipboard，再打开「允许完全访问」。系统询问是否允许粘贴时选「允许粘贴」。
3. 复制一段文字，在备忘录等 App 的输入框里长按地球键切到 Clipboard，点记录即可插入。

## 使用

- 历史记录按最近复制时间排列。整条圆角按键都可以点，文本直接插入，图片复制后可在输入框粘贴。
- 空格、退格以及换行或确认键在底部。最后一键会根据输入框显示「完成」「发送」「搜索」等名称，具体动作由输入框处理。
- 点顶部垃圾桶进入删除模式，再点需要删除的记录，点「完成」退出。「清空」会再次确认。删除历史保留系统剪贴板当前内容。
- 主 App 右上角的齿轮打开键盘设置，可选择保留 7、15、30 或 90 天，以及插入后是否自动切换键盘。默认保留 30 天。此页调起 Clipboard 的专用设置面板，直接写入键盘的本地存储。系统设置负责启用和完全访问。
- 键盘打开时收集当前剪贴板。键盘关闭期间若连续复制多项，下次打开时只能收集当时仍在剪贴板上的内容。所有数据保存在设备上。

## 从旧版更新

沿用原签名标识、原包类型覆盖安装，键盘会继续使用原有的数据库和设置。无共享组版用 `-local.ipa`。原来使用共享组或 SideStore 共享组版的用户可继续用 `-resign.ipa`。如需保留只在 1.0.4 主 App 中的记录，更新前可在旧版完成最后一次同步。

| 签名组件 | 默认标识 |
| --- | --- |
| 主 App | `net.chkf.Clipboard` |
| 键盘扩展 | `net.chkf.Clipboard.keyboard` |
| 共享组版的 App Group | `group.net.chkf.Clipboard` |

## 构建与验证

在安装 Xcode 26、XcodeGen 和 iOS 26 模拟器的 Mac 上执行以下命令。

```sh
xcodegen generate
bash scripts/test-ios.sh
bash scripts/package-ipa.sh 1.1.0
```

真机 IPA 和 SHA-256 校验文件位于 `build/release/`。GitHub Actions 会在无共享组和有共享组的模拟器上测试真实键盘、主 App 和独立宿主，验证两个包中主 App 与扩展的签名。从 main 手动运行 iOS 工作流并勾选 publish 即可在检查通过后发布。
