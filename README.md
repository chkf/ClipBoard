# Clipboard

iOS 26 及以上版本的本地剪贴板键盘。在输入框里切到 Clipboard，可以保存当前剪贴板、按分类浏览历史、回填文本或取回图片。

## 安装

1. 在发布页下载 `Clipboard-版本-local.ipa`，用全能签重签整个 IPA，保留键盘扩展。用自己的 Apple ID 安装时，也可以在 SideStore 导入并保留扩展。[下载 Clipboard](https://github.com/chkf/ClipBoard/releases/latest) · [SideStore 安装指南](https://docs.sidestore.io/)
2. 在 iPhone「设置」→「通用」→「键盘」→「键盘」中添加 Clipboard，再打开「允许完全访问」。系统询问是否允许粘贴时选「允许粘贴」。
3. 复制一段文字，在备忘录等 App 的输入框里长按地球键切到 Clipboard，点记录即可插入。

## 键盘

- 点记录即可插入，右滑置顶，左滑后点「归类」或「删除」。分类栏可左右滑动，最右侧箭头展开全部分类。主 App 的「分类管理」可新建、改名和删除分类。全能签本地版保存分类时，在键盘上点「应用分类更改」。
- 右侧中键可以连续撤销归类、置顶、删除或整批清空。切走或收起键盘后，撤销结束。清空只处理「普通」中的未置顶记录。已归类或置顶的内容保留到手动移除。
- 轻点空格左边的切换键可切到下一个输入法，长按可从系统列表选择已启用的键盘。要用苹果数字页，切到苹果拼音或英文键盘后点「123」。要用苹果表情，长按选「表情符号」。Clipboard 已恢复简体中文语言标识，菜单里的语言名称由 iOS 按系统语言显示。[苹果的键盘切换接口](https://developer.apple.com/documentation/uikit/uiinputviewcontroller/handleinputmodelist%28from%3Awith%3A%29)
- 空格中央的键盘名淡出后，右下角显示「剪」。长按空格并左右拖动可移动光标，按住退格会连续删除光标前的文字。轻点垃圾桶会在中央询问，长按垃圾桶直接清空「普通」中未置顶的记录，点撤销可整批恢复。
- 键盘使用 UIKit 的键盘背景。输入框要求有内容才能搜索时，空框中的搜索键显示为灰色，输入后点亮。按键音跟随系统的键盘声音设置。[苹果键盘背景文档](https://developer.apple.com/documentation/uikit/uiinputview/style/keyboard) · [苹果按键音文档](https://developer.apple.com/documentation/uikit/uidevice/playinputclick%28%29)
- 主 App 右上角齿轮内可开关按键触感、设置插入后是否切换输入法，选择历史保留 7、15、30 或 90 天，或分别微调横屏和竖屏的键盘高度。
- 切到 Clipboard 时，键盘会保存当前可读取的剪贴板内容。键盘收起期间多次复制，再打开时通常只能取到最后一条。历史保存在手机上。

## 从旧版更新

沿用原签名标识、原包类型覆盖安装，键盘会继续使用原有的数据库和设置。无共享组版用 `-local.ipa`。原来使用共享组或 SideStore 共享组版的用户可继续用 `-resign.ipa`。如果 1.2.0 试用版主 App 显示还有待存记录，更新前可先用旧版的「存入键盘」。如需保留只在 1.0.4 主 App 中的记录，更新前可在旧版完成最后一次同步。

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
bash scripts/package-ipa.sh 1.3.1
```

真机 IPA 和 SHA-256 校验文件位于 `build/release/`。GitHub Actions 会在无共享组和有共享组的模拟器上测试真实键盘、主 App 和独立宿主，验证两个包中主 App 与扩展的签名。从 main 手动运行 iOS 工作流并勾选 publish 即可在检查通过后发布。
