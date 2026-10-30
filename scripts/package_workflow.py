"""Generate a portable Alfred workflow; never edits Alfred's installed preferences."""
import pathlib
import plistlib
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
STAGING = DIST / "SoundFinder"
STAGING.mkdir(parents=True, exist_ok=True)
shutil.copy2(sys.argv[1], STAGING / "soundfinder")

FILTER = "5E81A838-D56A-4C4E-8C39-42C25C708A7B"
ACTION = "DBFF0AC9-878A-43E2-A92F-19A3DBCF2E50"
NOTIFY = "C438A67F-37B8-48B8-89B9-A4FD93611EDD"
workflow = {
    "bundleid": "local.afinder.soundfinder",
    "name": "SoundFinder",
    "createdby": "AFinder",
    "description": "Find audio sources and Chrome tabs / 查找声音来源与 Chrome 标签页",
    "version": "1.2.0",
    "disabled": False,
    "variables": {"soundfinder_chrome_ax": "1", "soundfinder_language": "auto"},
    "userconfigurationconfig": [{
        "variable": "soundfinder_language", "type": "popupbutton",
        "label": "UI language / 界面语言",
        "description": "Language for results, details and notifications / 结果、详情和通知的语言。"
                       "Auto follows the first macOS language preference / 自动跟随 macOS 首选语言。",
        "config": {"default": "auto", "pairs": [
            ["Auto (macOS) / 跟随系统", "auto"],
            ["English", "en"],
            ["简体中文", "zh-Hans"],
        ]},
    }, {
        "variable": "soundfinder_chrome_ax", "type": "checkbox",
        "label": "Chrome tabs / Chrome 标签页",
        "description": "Uses Accessibility audio markers (English Chrome only); permission required, no extension. / "
                       "读取英文 Chrome 的辅助功能声音标记；需要权限，无需扩展。",
        "config": {"default": True, "required": False,
                   "text": "Enable Chrome tab detection / 启用 Chrome 标签页检测"},
    }],
    # Alfred stores these fields statically, so import/configuration help is bilingual.
    "readme": """# SoundFinder

Type `sound` to find active audio output apps and Chrome audio tabs.
Press Return to focus the existing app or original tab; ⌘C copies details.

**UI language:** `auto` follows the first macOS language preference
(Simplified Chinese → 简体中文; other languages → English).
Choose English or 简体中文 in Configure Workflow to override it.

Requires macOS 14.4+ and Alfred 5 Powerpack. Chrome tab detection needs
Accessibility permission and an English Chrome interface. No extension needed.
An active output stream may contain silent data. This package is ad-hoc signed,
not Apple-notarized. See the bundled README.md for full instructions.

---

输入 `sound` 查找活跃音频输出应用和 Chrome 发声标签页。
回车切到原应用或原标签页；⌘C 复制详情。

**界面语言：** `auto` 跟随 macOS 首选语言（简体中文显示中文，其余显示英文）。
在工作流配置的下拉菜单中选择 English 或 简体中文可覆盖系统设置。

需要 macOS 14.4+ 与 Alfred 5 Powerpack。Chrome 标签页检测需要辅助功能权限，
并且仍只适配英文 Chrome 界面，无需浏览器扩展。
活跃输出流可能包含静默数据。安装包采用 ad-hoc 签名，未经 Apple 公证。
完整说明见安装包内的 README.zh-CN.md。
""",
    "objects": [
        {
            "uid": FILTER, "type": "alfred.workflow.input.scriptfilter", "version": 3,
            "config": {
                "keyword": "sound", "withspace": True, "argumenttype": 1,
                "argumenttreatemptyqueryasnil": True, "argumenttrimmode": 0,
                "title": "Find audio sources / 查找声音来源",
                "subtext": "Active output streams / 活跃输出流 · 2s refresh / 每 2 秒刷新",
                "runningsubtext": "Scanning audio sources… / 正在检测声音来源…",
                "script": './soundfinder alfred "$1"', "scriptfile": "",
                "type": 0, "scriptargtype": 1, "escaping": 0,
                "alfredfiltersresults": False, "alfredfiltersresultsmatchmode": 0,
                "queuemode": 1, "queuedelaymode": 0,
                "queuedelayimmediatelyinitially": True, "queuedelaycustom": 1,
            },
        },
        {
            "uid": ACTION, "type": "alfred.workflow.action.script", "version": 2,
            "config": {
                "script": './soundfinder activate "$1"', "scriptfile": "",
                "type": 0, "scriptargtype": 1, "escaping": 0,
            },
        },
        {
            "uid": NOTIFY, "type": "alfred.workflow.output.notification", "version": 1,
            "config": {
                "title": "SoundFinder", "text": "{query}",
                "onlyshowifquerypopulated": True, "removeextension": False,
                "lastpathcomponent": False,
            },
        },
    ],
    "connections": {
        FILTER: [{"destinationuid": ACTION, "modifiers": 0, "modifiersubtext": "",
                  "vitoclose": False}],
        ACTION: [{"destinationuid": NOTIFY, "modifiers": 0, "modifiersubtext": "",
                  "vitoclose": False}],
    },
    "uidata": {
        FILTER: {"xpos": 80, "ypos": 80},
        ACTION: {"xpos": 350, "ypos": 80},
        NOTIFY: {"xpos": 610, "ypos": 80},
    },
}
(STAGING / "info.plist").write_bytes(plistlib.dumps(workflow))
shutil.copy2(ROOT / "README.md", STAGING / "README.md")
shutil.copy2(ROOT / "README.zh-CN.md", STAGING / "README.zh-CN.md")
shutil.copy2(ROOT / "icon.png", STAGING / "icon.png")
(STAGING / "docs").mkdir(exist_ok=True)
shutil.copy2(ROOT / "docs/chrome-ax-validation.md", STAGING / "docs/chrome-ax-validation.md")
(STAGING / "docs/images").mkdir(exist_ok=True)
shutil.copy2(ROOT / "docs/images/demo-en.png", STAGING / "docs/images/demo-en.png")
archive = DIST / "SoundFinder-1.2.0.alfredworkflow"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
    for name in ["info.plist", "soundfinder", "icon.png", "README.md",
                 "README.zh-CN.md", "docs/chrome-ax-validation.md", "docs/images/demo-en.png"]:
        output.write(STAGING / name, name)
print(f"工作流已生成：{archive}")
