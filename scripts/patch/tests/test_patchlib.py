from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "patchlib.py"
spec = importlib.util.spec_from_file_location("patchlib", MODULE_PATH)
assert spec and spec.loader
patchlib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patchlib)


class PatchLibTests(unittest.TestCase):
    def test_version_triplet(self) -> None:
        self.assertEqual(patchlib.parse_version("1.9.0"), (1, 9, 0))
        self.assertEqual(patchlib.parse_version("1.9.12"), (1, 9, 12))
        for value in ("1.09.0", "v1.9.0", "1.9", "1.9.0.1", "1.-1.0"):
            with self.assertRaises(patchlib.PatchError):
                patchlib.parse_version(value)

    def test_repository_path_safety(self) -> None:
        self.assertEqual(str(patchlib.safe_rel_path("src/Foo.cs")), "src/Foo.cs")
        for value in ("../Foo.cs", "/tmp/Foo.cs", ".git/config", ".work/state.json", "a\\b"):
            with self.assertRaises(patchlib.PatchError):
                patchlib.safe_rel_path(value)

    def test_atomic_json_write(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "state" / "value.json"
            patchlib.atomic_write_json(path, {"ok": True})
            self.assertEqual(json.loads(path.read_text()), {"ok": True})

    def test_origin_normalization(self) -> None:
        expected = "alescis-wuin/nexali"
        self.assertEqual(patchlib.normalize_github_origin("git@github.com:alescis-wuin/nexali.git"), expected)
        self.assertEqual(patchlib.normalize_github_origin("https://github.com/alescis-wuin/nexali.git"), expected)
        self.assertEqual(patchlib.normalize_github_origin("ssh://git@github.com/alescis-wuin/nexali.git"), expected)


if __name__ == "__main__":
    unittest.main()
