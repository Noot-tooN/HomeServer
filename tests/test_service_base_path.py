import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("base_path", Path(__file__).parents[1] / "scripts/service_base_path.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BasePathTest(unittest.TestCase):
    def test_preserves_jackett_settings_and_original_backup_on_repeated_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ServerConfig.json"
            original = {"APIKey": "TEST_ONLY", "AdminPassword": "TEST_ONLY", "BasePathOverride": "", "Port": 9117}
            path.write_text(json.dumps(original))
            module.configure("jackett", path, "/jackett")
            updated = json.loads(path.read_text())
            self.assertEqual(updated, dict(original, BasePathOverride="/jackett"))
            before = path.stat().st_mtime_ns
            module.configure("jackett", path, "/jackett")
            self.assertEqual(before, path.stat().st_mtime_ns)
            self.assertEqual(json.loads(path.with_name(path.name + ".before-subpath").read_text()), original)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_preserves_jellyfin_network_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "network.xml"
            path.write_text('<NetworkConfiguration><BaseUrl /><InternalHttpPort>8096</InternalHttpPort><KnownProxies><string>127.0.0.1</string></KnownProxies></NetworkConfiguration>')
            module.configure("jellyfin", path, "/media")
            root = ET.parse(path).getroot()
            self.assertEqual(root.findtext("BaseUrl"), "/media")
            self.assertEqual(root.findtext("InternalHttpPort"), "8096")
            self.assertEqual(root.findtext("KnownProxies/string"), "127.0.0.1")
            before = path.read_bytes()
            module.configure("jellyfin", path, "/media")
            self.assertEqual(path.read_bytes(), before)

    def test_malformed_config_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config"
            for kind in ["jackett", "jellyfin"]:
                path.write_text("INVALID TEST CONFIG")
                with self.assertRaises(Exception):
                    module.configure(kind, path, "/app")
                self.assertEqual(path.read_text(), "INVALID TEST CONFIG")
                self.assertFalse(path.with_name(path.name + ".before-subpath").exists())
