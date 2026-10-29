"""Validate the actual packaged Alfred graph, not just the Swift executable."""
import pathlib
import plistlib
import re
import struct
import sys
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


class WorkflowTests(unittest.TestCase):
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

    def test_alfred_import_help_stays_chinese(self):
        self.assertEqual(workflow["readme"], readmes["README.zh-CN.md"])

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
