"""Real certificate/code-signing regression; uses an isolated temporary Keychain."""
import importlib.util
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("local_signing", ROOT / "Configuration/signing/local_signing.py")
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


@unittest.skipUnless(sys.platform == "darwin", "requires macOS codesign and Keychain")
class LocalSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="airisland-signing-tests-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.keychain = cls.root / "isolated.keychain-db"
        cls.addClassCleanup(lambda: subprocess.run(["security", "delete-keychain", str(cls.keychain)], capture_output=True))
        password = secrets.token_urlsafe(32)
        signing.run(["security", "create-keychain", "-p", password, cls.keychain])
        cls.state = signing.create_identity(cls.root / "identity", cls.keychain)
        cls.other = signing.create_identity(cls.root / "other-identity", cls.keychain)
        source = cls.root / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.executable = cls.root / "main"
        signing.run(["xcrun", "clang", source, "-o", cls.executable])

    def make_app(self, name):
        app = self.root / name
        helper = app / "Contents/XPCServices/AirIslandHelper.xpc"
        for bundle, identifier in [(helper, signing.HELPER_ID), (app, signing.APP_ID)]:
            binary = bundle / "Contents/MacOS/AirIsland"
            binary.parent.mkdir(parents=True)
            shutil.copy2(self.executable, binary)
            with (bundle / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleIdentifier": identifier, "CFBundleExecutable": "AirIsland",
                               "CFBundleVersion": "1"}, stream)
            signing.run(["codesign", "--force", "--sign", "-", bundle])
        return app

    def test_distinct_builds_keep_identity_and_reject_another_key(self):
        first, second, other = [self.make_app(name) for name in ("first.app", "second.app", "other.app")]
        with (second / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        info["CFBundleVersion"] = "2"
        with (second / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        for app, state in [(first, self.state), (second, self.state), (other, self.other)]:
            signing.sign_app(app, state)
        for relative, identifier in [(".", signing.APP_ID), ("Contents/XPCServices/AirIslandHelper.xpc", signing.HELPER_ID)]:
            condition = "=" + signing.requirement(identifier, self.state["fingerprint"]).removeprefix("designated => ")
            for app in (first, second):
                signing.run(["codesign", "--verify", "--strict", "-R", condition, app / relative])
            rejected = subprocess.run(["codesign", "--verify", "-R", condition, str(other / relative)], capture_output=True)
            self.assertNotEqual(rejected.returncode, 0, "Another signing key inherited the identity")
        # Updating content really changes the code directory hash while retaining its DR.
        def cdhash(app):
            return subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True).stderr.split(b"CDHash=")[1].splitlines()[0]
        self.assertNotEqual(cdhash(first), cdhash(second))

    def test_existing_identity_is_reused(self):
        again = signing.create_identity(self.root / "identity", self.keychain)
        self.assertEqual(again, self.state)
        self.assertFalse(list((self.root / "identity").glob("*.p12")))
        self.assertFalse(list((self.root / "identity").glob("*key*")))

    def test_missing_identity_fails_instead_of_regenerating(self):
        with self.assertRaises(RuntimeError):
            signing.load_identity(self.root / "missing")

    def test_concurrent_initialization_reuses_one_identity(self):
        with ThreadPoolExecutor(max_workers=2) as workers:
            states = list(workers.map(lambda _: signing.create_identity(self.root / "concurrent", self.keychain), range(2)))
        self.assertEqual(states[0], states[1])

    def test_wrong_bundle_is_rejected(self):
        app = self.make_app("wrong.app")
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "unrelated.app"}, stream)
        with self.assertRaises(RuntimeError):
            signing.sign_app(app, self.state)


if __name__ == "__main__":
    unittest.main()
