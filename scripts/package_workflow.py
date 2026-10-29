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
    "name": "声音来源 · SoundFinder",
    "createdby": "AFinder",
    "description": "输入 sound，查找音频输出应用/进程及 Chrome 发声标签页，无需浏览器扩展。",
    "version": "1.1.1",
    "disabled": False,
    "variables": {"soundfinder_chrome_ax": "1"},
    "userconfigurationconfig": [{
        "variable": "soundfinder_chrome_ax", "type": "checkbox",
        "label": "Chrome 标签页",
        "description": "通过 macOS 辅助功能读取声音标记；需要辅助功能权限，无需 Chrome 扩展。",
        "config": {"default": True, "required": False, "text": "启用 Chrome 发声标签页检测"},
    }],
    "readme": (ROOT / "README.md").read_text(),
    "objects": [
        {
            "uid": FILTER, "type": "alfred.workflow.input.scriptfilter", "version": 3,
            "config": {
                "keyword": "sound", "withspace": True, "argumenttype": 1,
                "argumenttreatemptyqueryasnil": True, "argumenttrimmode": 0,
                "title": "查找声音来源", "subtext": "列出活跃音频输出流 · 每 2 秒刷新",
                "runningsubtext": "正在检测声音来源…",
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
                "title": "声音来源", "text": "{query}",
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
(STAGING / "docs").mkdir(exist_ok=True)
shutil.copy2(ROOT / "docs/chrome-ax-validation.md", STAGING / "docs/chrome-ax-validation.md")
archive = DIST / "SoundFinder-1.1.1.alfredworkflow"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
    for name in ["info.plist", "soundfinder", "README.md", "docs/chrome-ax-validation.md"]:
        output.write(STAGING / name, name)
print(f"工作流已生成：{archive}")
