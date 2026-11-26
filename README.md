# Clipboard

适用于 iOS 26 及以上的本地剪贴板。打开主 App 或切换到 Clipboard 键盘时，系统允许读取的文本和图片会自动进入共享历史。两个入口都未活动时，下一次只能取到剪贴板的当前内容。

## 安装

1. 从 [Releases](https://github.com/chkf/ClipBoard/releases/latest) 下载 `Clipboard-版本-resign.ipa`。同目录的 `.sha256` 可用 `shasum -a 256 -c 文件名.sha256` 验证。
2. 用支持键盘扩展和 App Groups 的 Apple 签名配置重签 IPA。先签嵌入的 `ClipboardKeyboard.appex`，再签 `Clipboard.app`。主 App 与扩展各用一份匹配设备和标识的描述文件，两者须授权同一 App Group。发布包附带用于重签的临时签名。
3. 安装重签后的 IPA。在「设置」→「通用」→「键盘」→「键盘」→「添加新键盘」中选择 Clipboard，点进该键盘并开启「允许完全访问」。
4. 首次跨 App 读取时按需允许粘贴。在支持第三方键盘的输入框中，用地球键切换至 Clipboard。安全输入框及限制第三方键盘的 App 使用系统键盘。

| 签名配置 | 发布包的值 |
| --- | --- |
| 主 App | `net.chkf.Clipboard` |
| 键盘扩展 | `net.chkf.Clipboard.keyboard` |
| App Group | `group.net.chkf.Clipboard` |

若使用自己的标识，请将两个 Info.plist 的 `ClipboardAppGroup` 和两份签名的 `com.apple.security.application-groups` 改为已注册的同一个组。也可从源码构建，在 `project.yml` 中设置 `CLIPBOARD_BUNDLE_ID`、`CLIPBOARD_APP_GROUP` 并在 Xcode 中选择自己的开发团队。

## 使用

- 主 App 中点击记录复制完整内容，长按预览，左滑删除。齿轮按钮可修改保留期限、插入后切换键盘或清空历史。
- 键盘中点击文本直接插入，点击图片后在宿主输入框中粘贴。插入后的自动切换默认关闭，开启时由系统决定下一个键盘。
- 默认保留 30 天，可选 7、15、30 或 90 天。再次复制相同内容会更新排序。删除记录后，系统剪贴板仍可粘贴原内容。
- 文本、原图、缩略图及设置位于有文件保护的共享容器内。所有功能均可离线使用。

## 构建与验证

在 Mac 上安装 Xcode 26、XcodeGen 和 iOS 26 模拟器后，在仓库根目录构建并测试。

```sh
xcodegen generate
bash scripts/test-ios.sh
bash scripts/package-ipa.sh 1.0.1
```

真机 IPA 输出到 `build/release/`。在 GitHub Actions 的「iOS build and release」工作流选择 `main` 并勾选 `publish`，模拟器测试和真机包校验通过后，工作流会为本次提交创建版本标签并发布 IPA 和校验文件。也可以直接推送与 `MARKETING_VERSION` 对应的 `vX.Y.Z` 标签触发发布。测试用的宿主 App 只安装在模拟器中。
