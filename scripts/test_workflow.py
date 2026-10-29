"""Validate the actual packaged Alfred graph, not just the Swift executable."""
import pathlib
import plistlib
import struct
import sys
import unittest
import zipfile

archive = pathlib.Path(sys.argv[1])
sys.argv = sys.argv[:1]
with zipfile.ZipFile(archive) as package:
    workflow = plistlib.loads(package.read("info.plist"))
    icon = package.read("icon.png")


class WorkflowTests(unittest.TestCase):
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
