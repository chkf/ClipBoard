# Clipboard

iOS 26 及以上版本的本地剪贴板键盘。可以在键盘里回填文本、取回图片，也可以从控制中心开启跨 App 连续复制。

## 安装

1. 在发布页下载 `Clipboard-版本-local.ipa`，用全能签重签整个 IPA，保留键盘和控制中心两个扩展。用自己的 Apple ID 安装时，也可以在 SideStore 导入并保留扩展。[下载 Clipboard](https://github.com/chkf/ClipBoard/releases/latest) · [SideStore 安装指南](https://docs.sidestore.io/)
2. 在 iPhone「设置」→「通用」→「键盘」→「键盘」中添加 Clipboard，再打开「允许完全访问」。系统询问是否允许粘贴时选「允许粘贴」。
3. 复制一段文字，在备忘录等 App 的输入框里长按地球键切到 Clipboard，点记录即可插入。

## 连续复制

1. 覆盖安装后先打开一次 Clipboard。长按控制中心空白处，点「添加控制」，搜索 Clipboard，添加带剪贴板图标的「连续复制」。点一下会打开主 App 并启动画中画。如果旧控件仍为空白，可移除后重新添加。
2. 回到要复制的 App，照常选中内容并点「复制」。可以把小窗拖到屏幕左侧或右侧收起，点边缘的小把手可拉回。画中画和支持实时活动的灵动岛显示已保存条数。[iPhone 画中画手势](https://support.apple.com/guide/iphone/multitask-with-picture-in-picture-iphcc3587b5d/ios)
3. 再点控制中心开关、点灵动岛展开后的停止按钮或关闭画中画，都可结束收集。锁屏结束本次收集，解锁后需自行重新开启。若 iOS 询问是否允许从其他 App 粘贴，请点「允许粘贴」。可在「设置」→「App」→「Clipboard」中查看系统提供的粘贴权限。

共享组版收到的条目直接进入键盘数据库。全能签版把连拷记录保存在主 App 的本机收件箱。首次结束后，在出现的 Clipboard 键盘点「存入键盘」，即可一次收下整批。如果系统无法识别接收方，主 App 会请你确认当前键盘。以后切到键盘时会尝试自动接收近期小条目。大图、系统结束进程后留下的记录等，都可以回「连续复制」点「存入键盘」补齐。传送中断可重试，键盘已确认的记录会去重。

如果 Clipboard 自带的控制图标是空白的，可以在主 App「连续复制」里启用「打开 Clipboard 时开始连拷」。然后在控制中心添加苹果的「打开 App」控件，选 Clipboard。回到其他 App 后点这个控件就会开始连拷。开启这个选项后，点桌面的 Clipboard 图标也会启动收集。收集中再次打开只显示计数和停止按钮。

如需保留打开主 App 时的默认行为，可以改用苹果的「快捷指令」控件。在「快捷指令」里新建指令，用「URL」和「打开 URL」两个动作打开 `clipboard-collect://toggle`，保存后在控制中心选择这条指令。

## 键盘

- 点历史键帽的文字或右侧空白都可插入。向右滑动一条记录可置顶或取消置顶，向左滑动可删除。置顶记录始终在最前面，也会保留在定期清理和清空操作之后。
- 右侧有清空、搜索和长退格键。搜索支持原文、拼音和首字母。底排提供数字、Emoji、空格和随当前输入框变化的回车键。点剪贴板图标可回到历史。
- 主 App 右上角的齿轮里可选择历史保留 7、15、30 或 90 天，设置插入后是否切换输入法，也可分别微调横屏和竖屏时的键盘高度。
- 平时切到键盘会保存当时可读取的剪贴板。需要在键盘收起时保存多次复制，须先开启连续复制。历史和连拷记录都留在手机上。

## 从旧版更新

沿用原签名标识、原包类型覆盖安装，键盘会继续使用原有的数据库和设置。无共享组版用 `-local.ipa`。原来使用共享组或 SideStore 共享组版的用户可继续用 `-resign.ipa`。如需保留只在 1.0.4 主 App 中的记录，更新前可在旧版完成最后一次同步。

| 签名组件 | 默认标识 |
| --- | --- |
| 主 App | `net.chkf.Clipboard` |
| 键盘扩展 | `net.chkf.Clipboard.keyboard` |
| 控制中心和灵动岛扩展 | `net.chkf.Clipboard.controls` |
| 共享组版的 App Group | `group.net.chkf.Clipboard` |

## 构建与验证

在安装 Xcode 26、XcodeGen 和 iOS 26 模拟器的 Mac 上执行以下命令。

```sh
xcodegen generate
bash scripts/test-ios.sh
bash scripts/package-ipa.sh 1.2.1
```

真机 IPA 和 SHA-256 校验文件位于 `build/release/`。GitHub Actions 会在无共享组和有共享组的模拟器上测试真实键盘、主 App 和独立宿主，验证两个包中主 App 与扩展的签名。从 main 手动运行 iOS 工作流并勾选 publish 即可在检查通过后发布。
