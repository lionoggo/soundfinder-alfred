"""Validate the actual packaged Alfred graph, not just the Swift executable."""
import pathlib
import plistlib
import re
import struct
import sys
import json
import os
import subprocess
import tempfile
import unittest
import zipfile

archive = pathlib.Path(sys.argv[1])
sys.argv = sys.argv[:1]
with zipfile.ZipFile(archive) as package:
    workflow = plistlib.loads(package.read("info.plist"))
    icon = package.read("icon.png")
    readmes = {name: package.read(name).decode("utf-8")
               for name in ["README.md", "README.zh-CN.md"]}
    demo = package.read("docs/images/demo-en.png")
    executable = package.read("soundfinder")


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="soundfinder-package-test-")
        cls.binary = pathlib.Path(cls.temp.name) / "soundfinder"
        cls.binary.write_bytes(executable)
        cls.binary.chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_binary(self, language, *args):
        environment = dict(os.environ, soundfinder_language=language, soundfinder_chrome_ax="0")
        return subprocess.run([str(self.binary), *args], env=environment,
                              capture_output=True, text=True, timeout=10)

    def test_packaged_binary_outputs_both_ui_languages(self):
        # An impossible query avoids exposing app/device names in test output.
        titles = {
            "en": {"No active audio output streams found", "No matching audio sources"},
            "zh-Hans": {"暂未发现活跃音频输出流", "没有匹配的声音来源"},
        }
        for language, expected in titles.items():
            with self.subTest(language=language):
                result = self.run_binary(language, "alfred", "__soundfinder_test_no_match_8b5ddf__")
                self.assertEqual(result.returncode, 0)
                data = json.loads(result.stdout)
                self.assertIn(data["items"][0]["title"], expected)
                self.assertIs(data["items"][0]["valid"], False)
                self.assertEqual(data["rerun"], 2)

    def test_packaged_binary_localizes_safe_activation_failures(self):
        expected = {"en": "Unable to switch: Missing target app path",
                    "zh-Hans": "无法切换：缺少目标应用路径"}
        for language, text in expected.items():
            with self.subTest(language=language):
                result = self.run_binary(language, "activate")
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout.strip(), text)
                invalid = self.run_binary(language, "activate", "chrome-tab:invalid")
                self.assertEqual(invalid.returncode, 0)
                self.assertEqual(invalid.stdout.strip(), {
                    "en": "Unable to switch: invalid tab argument. Run sound again.",
                    "zh-Hans": "无法跳转：标签页参数无效，请重新输入 sound。",
                }[language])

    def test_packaged_binary_localizes_cli_usage(self):
        for language, prefix in [("en", "Usage:"), ("zh-Hans", "用法：")]:
            with self.subTest(language=language):
                result = self.run_binary(language, "unknown-command")
                self.assertEqual(result.returncode, 1)
                self.assertTrue(result.stderr.startswith(prefix))

    def test_demo_image_is_packaged_and_referenced_in_both_languages(self):
        root = pathlib.Path(__file__).resolve().parent.parent
        self.assertEqual(demo[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(demo, (root / "docs/images/demo-en.png").read_bytes())
        for text in readmes.values():
            self.assertIn("](docs/images/demo-en.png)", text)

    def test_both_readmes_are_packaged_with_language_links(self):
        self.assertIn("## Installation", readmes["README.md"])
        self.assertIn("[简体中文](README.zh-CN.md)", readmes["README.md"])
        self.assertIn("## 安装", readmes["README.zh-CN.md"])
        self.assertIn("[English](README.md)", readmes["README.zh-CN.md"])
        root = pathlib.Path(__file__).resolve().parent.parent
        for name, text in readmes.items():
            self.assertEqual(text, (root / name).read_text(encoding="utf-8"))

    def test_alfred_import_help_is_bilingual(self):
        self.assertIn("UI language", workflow["readme"])
        self.assertIn("界面语言", workflow["readme"])
        self.assertIn("README.md", workflow["readme"])
        self.assertIn("README.zh-CN.md", workflow["readme"])

    def test_language_configuration_is_passed_to_both_scripts(self):
        self.assertEqual(workflow["variables"]["soundfinder_language"], "auto")
        config = next(item for item in workflow["userconfigurationconfig"]
                      if item["variable"] == "soundfinder_language")
        self.assertEqual(config["type"], "popupbutton")
        self.assertEqual(config["config"]["default"], "auto")
        self.assertEqual(config["config"]["pairs"], [
            ["Auto (macOS) / 跟随系统", "auto"],
            ["English", "en"],
            ["简体中文", "zh-Hans"],
        ])
        # Workflow variables are inherited by both nodes; no per-node override.
        for node in workflow["objects"]:
            self.assertNotIn("variables", node)

    def test_static_prompts_are_bilingual_and_notification_title_is_neutral(self):
        node = next(item for item in workflow["objects"]
                    if item["type"] == "alfred.workflow.input.scriptfilter")
        self.assertIn("Find audio sources", node["config"]["title"])
        self.assertIn("查找声音来源", node["config"]["title"])
        self.assertIn("Scanning", node["config"]["runningsubtext"])
        self.assertIn("正在检测", node["config"]["runningsubtext"])
        chrome = next(item for item in workflow["userconfigurationconfig"]
                      if item["variable"] == "soundfinder_chrome_ax")
        self.assertIn("Enable Chrome", chrome["config"]["text"])
        self.assertIn("启用 Chrome", chrome["config"]["text"])
        notification = next(item for item in workflow["objects"]
                            if item["type"] == "alfred.workflow.output.notification")
        self.assertEqual(notification["config"]["title"], "SoundFinder")
        self.assertEqual(workflow["version"], "1.2.0")

    def test_bilingual_shell_commands_match(self):
        def commands(text):
            return [
                line.strip()
                for block in re.findall(r"```sh\n(.*?)\n```", text, flags=re.DOTALL)
                for line in block.splitlines()
                if line.strip() and not line.strip().startswith("#")
            ]
        self.assertEqual(commands(readmes["README.md"]), commands(readmes["README.zh-CN.md"]))

    def test_workflow_icon_is_square_rgba_png(self):
        self.assertEqual(icon[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(icon[12:16], b"IHDR")
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", icon[16:29])
        self.assertEqual((width, height), (512, 512))
        self.assertEqual((bit_depth, color_type), (8, 6))

    def test_packaged_icon_matches_tracked_icon(self):
        source = pathlib.Path(__file__).resolve().parent.parent / "icon.png"
        self.assertEqual(icon, source.read_bytes())

    def test_return_closes_alfred_before_activation(self):
        """vitoclose=True means 'Don't close Alfred', not 'close Alfred'."""
        for edges in workflow["connections"].values():
            for edge in edges:
                self.assertIs(edge["vitoclose"], False)

    def test_every_connection_has_a_real_destination(self):
        objects = {item["uid"]: item for item in workflow["objects"]}
        for source, edges in workflow["connections"].items():
            self.assertIn(source, objects)
            for edge in edges:
                self.assertIn(edge["destinationuid"], objects)

    def test_selected_argument_is_passed_without_shell_interpolation(self):
        action = next(item for item in workflow["objects"]
                      if item["type"] == "alfred.workflow.action.script")
        self.assertEqual(action["config"]["scriptargtype"], 1)
        self.assertEqual(action["config"]["script"], './soundfinder activate "$1"')

    def test_filter_connects_to_action_and_notification(self):
        objects = {item["uid"]: item for item in workflow["objects"]}
        script_filter = next(item for item in workflow["objects"]
                             if item["type"] == "alfred.workflow.input.scriptfilter")
        action_id = workflow["connections"][script_filter["uid"]][0]["destinationuid"]
        self.assertEqual(objects[action_id]["type"], "alfred.workflow.action.script")
        notification_id = workflow["connections"][action_id][0]["destinationuid"]
        self.assertEqual(objects[notification_id]["type"], "alfred.workflow.output.notification")


if __name__ == "__main__":
    unittest.main()
