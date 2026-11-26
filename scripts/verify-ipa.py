import json
import plistlib
import subprocess
import sys
from pathlib import Path


def read_plist(path):
    return plistlib.loads(path.read_bytes())


app = Path(sys.argv[1])
version = sys.argv[2]
mode = sys.argv[3]
assert mode in ("local", "resign")
plugins = list((app / "PlugIns").glob("*.appex"))
assert {p.name for p in plugins} == {"ClipboardKeyboard.appex", "ClipboardControls.appex"}, plugins
keyboard = app / "PlugIns/ClipboardKeyboard.appex"
controls = app / "PlugIns/ClipboardControls.appex"
host = read_plist(app / "Info.plist")
ext = read_plist(keyboard / "Info.plist")
widget = read_plist(controls / "Info.plist")
assert host["NSSupportsLiveActivities"] and "audio" in host["UIBackgroundModes"]
assert widget["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
assert widget["CFBundleIdentifier"] == host["CFBundleIdentifier"] + ".controls"
assert any("clipboard-collect" in item["CFBundleURLSchemes"] for item in host["CFBundleURLTypes"])
for bundle in (app, controls):
    metadata = json.loads((bundle / "Metadata.appintents/extract.actionsdata").read_bytes())
    intent = metadata["actions"]["ToggleCopyCollection"]
    assert any(parameter.get("name") == "target" for parameter in intent["parameters"]), intent
    assert "com.apple.link.systemProtocol.OpenEntity" in intent["systemProtocols"]
    if bundle == app:
        assert any(s["actionIdentifier"] == intent["identifier"] and s["systemImageName"] == "list.clipboard.fill"
                   for s in metadata["autoShortcuts"]), "The system Shortcuts action was not registered"
assert ext["CFBundleIdentifier"] == host["CFBundleIdentifier"] + ".keyboard"
assert ext["CFBundleVersion"] == host["CFBundleVersion"]
assert ext["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert ext["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"] is True
assert ext["NSExtension"]["NSExtensionAttributes"]["PrimaryLanguage"] == "zh-Hans-x-cliphist"
assert ext["NSExtension"]["NSExtensionPrincipalClass"].endswith(".KeyboardViewController")
group = host["ClipboardAppGroup"]
assert group.startswith("group.")
for bundle, info in [(app, host), (keyboard, ext), (controls, widget)]:
    binary = bundle / info["CFBundleExecutable"]
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    assert info["MinimumOSVersion"] == "26.0"
    assert info["CFBundleShortVersionString"] == version
    assert info["CFBundleVersion"] == host["CFBundleVersion"]
    if bundle != controls:
        assert info["ClipboardAppGroup"] == group
        assert info.get("ClipboardPrivateHistory", False) is (mode == "local")
    assert "ALTAppGroups" not in info, "signer metadata belongs to the re-signed package"
    assert "arm64" in subprocess.check_output(["lipo", "-archs", binary], text=True).split()
    subprocess.run(["codesign", "--verify", "--strict", bundle], check=True)
    xml = subprocess.check_output(["codesign", "--display", "--entitlements", "-", "--xml", bundle])
    entitlements = plistlib.loads(xml) if xml.strip() else {}
    if mode == "local" or bundle == controls:
        assert "com.apple.security.application-groups" not in entitlements
    else:
        assert entitlements["com.apple.security.application-groups"] == [group]
    assert not entitlements.get("get-task-allow")
    assert (bundle / "PrivacyInfo.xcprivacy").is_file()
    print(info["CFBundleIdentifier"], version, mode, "arm64 iPhoneOS")
