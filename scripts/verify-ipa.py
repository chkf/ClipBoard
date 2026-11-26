import plistlib
import subprocess
import sys
from pathlib import Path


def read_plist(path):
    return plistlib.loads(path.read_bytes())


app = Path(sys.argv[1])
version = sys.argv[2]
plugins = list((app / "PlugIns").glob("*.appex"))
assert len(plugins) == 1, plugins
keyboard = plugins[0]
host = read_plist(app / "Info.plist")
ext = read_plist(keyboard / "Info.plist")
assert ext["CFBundleIdentifier"] == host["CFBundleIdentifier"] + ".keyboard"
assert ext["CFBundleVersion"] == host["CFBundleVersion"]
assert ext["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert ext["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"] is True
assert ext["NSExtension"]["NSExtensionPrincipalClass"].endswith(".KeyboardViewController")
group = host["ClipboardAppGroup"]
assert group.startswith("group.")
for bundle, info in [(app, host), (keyboard, ext)]:
    binary = bundle / info["CFBundleExecutable"]
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    assert info["MinimumOSVersion"] == "26.0"
    assert info["CFBundleShortVersionString"] == version
    assert info["ClipboardAppGroup"] == group
    assert "arm64" in subprocess.check_output(["lipo", "-archs", binary], text=True).split()
    subprocess.run(["codesign", "--verify", "--strict", bundle], check=True)
    entitlements = plistlib.loads(subprocess.check_output(["codesign", "--display", "--entitlements", "-", "--xml", bundle]))
    assert entitlements["com.apple.security.application-groups"] == [group]
    assert not entitlements.get("get-task-allow")
    assert (bundle / "PrivacyInfo.xcprivacy").is_file()
    print(info["CFBundleIdentifier"], version, group, "arm64 iPhoneOS")
