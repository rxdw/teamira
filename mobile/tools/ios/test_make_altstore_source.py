"""Tests for make_altstore_source.py: python3 -m unittest discover -s tools/ios"""
import io, json, plistlib, sys, tempfile, unittest, zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import make_altstore_source as m  # noqa: E402


def make_ipa(path: Path, *, version="0.1.0", build="1", binary_plist=False, extra=None, entitlements=None):
    info = {"CFBundleIdentifier": "com.example.seenly", "CFBundleShortVersionString": version, "CFBundleVersion": build,
            "CFBundleDisplayName": "Seenly", "MinimumOSVersion": "13.0",
            "NSCameraUsageDescription": "Used to scan a code.", "UIDeviceFamily": [1]}
    info.update(extra or {})
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY if binary_plist else plistlib.FMT_XML))
        z.writestr("Payload/Runner.app/Runner", b"\0" * 100)
        if entitlements is not None:
            z.writestr("Payload/Runner.app/archived-expanded-entitlements.xcent", plistlib.dumps(entitlements))


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src = self.tmp / "ios" / "source.json"

    def run_tool(self, ipa, *extra):
        return m.main([str(ipa), "--ipa-url", "https://x.ru/ios/a.ipa", "--source", str(self.src), *extra])

    def test_creates_source_and_reads_facts_from_ipa_including_binary_plist(self):
        ipa = self.tmp / "a.ipa"; make_ipa(ipa, binary_plist=True)
        self.assertEqual(self.run_tool(ipa, "--notes", "первая"), 0)
        s = json.loads(self.src.read_text(encoding="utf-8"))
        app = s["apps"][0]
        self.assertEqual(app["bundleIdentifier"], "com.example.seenly")
        v = app["versions"][0]
        self.assertEqual((v["version"], v["buildVersion"], v["minOSVersion"], v["localizedDescription"]), ("0.1.0", "1", "13.0", "первая"))
        self.assertEqual(v["size"], ipa.stat().st_size)
        self.assertEqual(app["appPermissions"]["privacy"], {"NSCameraUsageDescription": "Used to scan a code."})
        self.assertEqual(app["appPermissions"]["entitlements"], [])

    def test_new_build_goes_first_and_old_stays(self):
        a, b = self.tmp / "a.ipa", self.tmp / "b.ipa"
        make_ipa(a, build="1"); make_ipa(b, build="2")
        self.run_tool(a); self.run_tool(b)
        versions = json.loads(self.src.read_text(encoding="utf-8"))["apps"][0]["versions"]
        self.assertEqual([v["buildVersion"] for v in versions], ["2", "1"])

    def test_same_build_is_refused_unless_replace(self):
        a = self.tmp / "a.ipa"; make_ipa(a, build="1")
        self.assertEqual(self.run_tool(a), 0)
        self.assertEqual(self.run_tool(a), 1)
        self.assertEqual(self.run_tool(a, "--replace"), 0)
        self.assertEqual(len(json.loads(self.src.read_text(encoding="utf-8"))["apps"][0]["versions"]), 1)

    def test_permissions_follow_the_newest_ipa(self):
        a, b = self.tmp / "a.ipa", self.tmp / "b.ipa"
        make_ipa(a, build="1")
        make_ipa(b, build="2", extra={"NSPhotoLibraryUsageDescription": "Pick an avatar."}, entitlements={
            "application-identifier": "T.x", "com.apple.developer.team-identifier": "T", "com.apple.security.application-groups": ["g"]})
        self.run_tool(a); self.run_tool(b)
        perms = json.loads(self.src.read_text(encoding="utf-8"))["apps"][0]["appPermissions"]
        self.assertEqual(sorted(perms["privacy"]), ["NSCameraUsageDescription", "NSPhotoLibraryUsageDescription"])
        self.assertEqual(perms["entitlements"], ["com.apple.security.application-groups"])

    def test_not_an_ipa_and_bad_url_are_clean_errors(self):
        bad = self.tmp / "bad.ipa"; bad.write_bytes(b"not a zip")
        self.assertEqual(self.run_tool(bad), 1)
        empty = self.tmp / "e.ipa"
        with zipfile.ZipFile(empty, "w") as z: z.writestr("readme.txt", "x")
        self.assertEqual(self.run_tool(empty), 1)
        ok = self.tmp / "ok.ipa"; make_ipa(ok)
        self.assertEqual(m.main([str(ok), "--ipa-url", "ftp://x", "--source", str(self.src)]), 1)
        self.assertFalse(self.src.exists())  # nothing written on failure


if __name__ == "__main__":
    unittest.main()
