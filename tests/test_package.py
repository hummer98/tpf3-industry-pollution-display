import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "tools"))
import package  # noqa: E402


class PackageTest(unittest.TestCase):
    # docs/images holds ~5 MB of README screenshots; only the cover in
    # _metadata belongs in the release, so pin what the zip may contain
    def test_release_holds_only_the_mod_files(self):
        names = [name for _, name in package.files_to_pack()]
        self.assertIn("mod.json", names)
        self.assertIn("_metadata/0.png", names)
        for name in names:
            self.assertFalse(name.startswith(("docs/", "tests/", "tools/", ".git")), name)
            self.assertTrue(name in ("mod.json", "strings.json")
                            or name.startswith(("content/", "_metadata/")), name)


if __name__ == "__main__":
    unittest.main()
