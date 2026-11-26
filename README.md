# Clipboard

适用于 iOS 26 及以上的本地剪贴板。打开主 App 或切换到 Clipboard 键盘时，系统允许读取的文本和图片会自动进入历史。两个入口都未活动时，下一次只能取到剪贴板的当前内容。

## 安装

### 用全能签等手机工具，无需 App Group

1. 在发布页下载 `Clipboard-版本-local.ipa`，在全能签中照常重签并安装整个 IPA，保留里面的键盘扩展。这个包的主 App 和键盘都使用自己的本地存储。[下载 Clipboard](https://github.com/chkf/ClipBoard/releases/latest)
2. 前往「设置」→「通用」→「键盘」→「键盘」→「添加新键盘」，添加 Clipboard，再允许完全访问。系统询问是否允许粘贴时选「允许粘贴」。
3. 打开 Clipboard 主 App。底部会自动打开同步输入框。如果出现其他键盘，用地球键选 Clipboard。初次配对时，核对主 App 和键盘显示的六位数相同，在上下两处各点一次「配对」。
4. 以后打开主 App 时，只要 Clipboard 键盘出现，两边就会自动合并，完成后键盘收起。也可以点「稍后」，继续管理历史，或点左上角的同步按钮重新连接。删除、清空和设置更改会在下次同步时传到键盘。

键盘单独打开时就能收集和插入已存内容。同步使用仅限本机的加密连接，数据不离开 iPhone，也不会写入系统剪贴板。主 App 或键盘退到后台会结束本次连接。

### 用自己的 Apple ID 和 SideStore

1. 在 iPhone 上设置好 SideStore，登录自己的 Apple ID，再从本项目发布页下载 `Clipboard-版本-resign.ipa` 到「文件」。[SideStore 安装指南](https://docs.sidestore.io/) · [下载 Clipboard](https://github.com/chkf/ClipBoard/releases/latest)
2. 在 SideStore 的「My Apps」点「＋」，选中 IPA。出现扩展选项时，选 **Keep App Extensions (Register App ID for Each Extension)**，让 SideStore 为主 App 和键盘分别签名。自 v1.0.2 起，两者都会使用 SideStore 分配的 Clipboard 共享组。
3. 打开 Clipboard。进入系统「设置」→「通用」→「键盘」→「键盘」→「添加新键盘」，选 Clipboard，再打开「允许完全访问」。复制一行文字，打开 Clipboard 允许粘贴，然后到备忘录用地球键切换键盘，点击同一条记录试插入。

免费 Apple ID 可以在自己的设备上测试 App。描述文件有效期为 7 天，可在 SideStore 的 My Apps 中刷新。这个 IPA 使用两个 App ID。发布页的 `.sha256` 文件可用 `shasum -a 256 -c 文件名.sha256` 校验。[Apple 个人团队说明](https://developer.apple.com/cn/help/account/basics/about-your-developer-account/) · [iOS 功能支持表](https://developer.apple.com/cn/help/account/reference/supported-capabilities-ios/)

### 用已有证书或 Xcode

如果已有两个组件共用的 App Group，可选 `-resign.ipa` 直接共用同一个历史库。用全能签等证书工具时，导入同一张 `.p12` 证书，并确认签名工具能给以下两个组件分别匹配 `.mobileprovision`。两个描述文件都要包含这台设备的授权，并在 `com.apple.security.application-groups` 中授权同一个组。保留 `PlugIns/ClipboardKeyboard.appex`，先签扩展、再签主 App，最后安装整个 IPA。

| 签名配置 | 发布包的值 |
| --- | --- |
| 主 App | `net.chkf.Clipboard` |
| 键盘扩展 | `net.chkf.Clipboard.keyboard` |
| App Group | `group.net.chkf.Clipboard` |

证书工具没有写入 SideStore 的 `ALTAppGroups` 时，Clipboard 会先尝试配置的 `ClipboardAppGroup`，再尝试 `group.<重签后的主 App Bundle ID>`。若描述文件使用其他自定义组名，请在重签前将主 App 和键盘各自 `Info.plist` 的 `ClipboardAppGroup` 设为实际组名。仅有 `.p12` 无法赋予共享组权限。

在 Mac 上也可以从源码安装。在 `project.yml` 填写唯一的 `CLIPBOARD_BUNDLE_ID` 和自己的 `CLIPBOARD_APP_GROUP`，执行 `xcodegen generate`。在 Xcode 的 Signing & Capabilities 给 Clipboard 和 ClipboardKeyboard 两个 target 选择同一 Personal Team 和同一 App Group，连接 iPhone 后运行 Clipboard。

## 使用

- 主 App 中点击记录复制完整内容，长按预览，左滑删除。齿轮按钮可修改保留期限、插入后切换键盘或清空历史。
- 键盘中点击文本直接插入，点击图片后在宿主输入框中粘贴。插入后的自动切换默认关闭，开启时由系统决定下一个键盘。
- 默认保留 30 天，可选 7、15、30 或 90 天。再次复制相同内容会更新排序。删除记录后，系统剪贴板仍可粘贴原内容。
- 文本、原图、缩略图及设置均受 iOS 文件保护。共享组版使用组内的历史库，无共享组版在两个入口各自保存并在连接时合并。两种方式都可离线使用。

## 构建与验证

在 Mac 上安装 Xcode 26、XcodeGen 和 iOS 26 模拟器后，在仓库根目录构建并测试。

```sh
xcodegen generate
bash scripts/test-ios.sh
bash scripts/package-ipa.sh 1.0.3
```

真机 IPA 输出到 `build/release/`。在 GitHub Actions 的「iOS build and release」工作流选择 `main` 并勾选 `publish`，模拟器测试和真机包校验通过后，工作流会为本次提交创建版本标签并发布 IPA 和校验文件。也可以直接推送与 `MARKETING_VERSION` 对应的 `vX.Y.Z` 标签触发发布。测试用的宿主 App 只安装在模拟器中。
