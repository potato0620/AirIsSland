from __future__ import annotations

import base64
import copy
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_update import FEED_URL, RELEASES, SPARKLE, build_number, feed_builds, validate_app, validate_generated_feed


class PrepareUpdateTests(unittest.TestCase):
    def setUp(self):
        self.info = {
            "CFBundleIdentifier": "theboringteam.boringnotch",
            "CFBundleShortVersionString": "2.8.10", "CFBundleVersion": "305",
            "SUFeedURL": FEED_URL, "SUPublicEDKey": "test-public-key",
            "SUEnableInstallerLauncherService": True, "SUVerifyUpdateBeforeExtraction": True,
            "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False,
        }

    def test_accepts_matching_stable_app_with_increasing_build(self):
        self.assertEqual(validate_app(self.info, "test-public-key", [(304, 0, 0)]), ("2.8.10", "305"))

    def test_rejects_equal_or_lower_build_including_dotted_previous_build(self):
        for previous in [(305, 0, 0), (306, 0, 0), (305, 1, 1)]:
            with self.subTest(previous=previous), self.assertRaises(ValueError):
                validate_app(self.info, "test-public-key", [previous])

    def test_rejects_incorrect_app_identity_or_update_configuration(self):
        changes = {
            "CFBundleIdentifier": "another.app", "SUPublicEDKey": "another-key",
            "SUFeedURL": "https://example.com/feed.xml", "CFBundleVersion": "invalid",
            "CFBundleShortVersionString": "2.8.10-beta.1",
            "SUEnableInstallerLauncherService": False, "SUVerifyUpdateBeforeExtraction": False,
            "SUEnableAutomaticChecks": True, "SUAllowsAutomaticUpdates": True,
        }
        for key, value in changes.items():
            info = copy.deepcopy(self.info)
            info[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_app(info, "test-public-key", [])

    def test_build_order_normalizes_missing_components(self):
        self.assertEqual(build_number("305"), build_number("305.0.0"))
        self.assertGreater(build_number("305.0.1"), build_number("305"))
        self.assertGreater(build_number("306"), build_number("305.99.99"))
        for value in ["", "1.2.3.4", "-1", "1-beta"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_number(value)

    def test_previous_feed_reads_both_sparkle_version_encodings(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / "appcast.xml"
            feed.write_text(f'''<rss xmlns:sparkle="{SPARKLE[1:-1]}"><channel>
                <item><sparkle:version>305</sparkle:version><enclosure url="{RELEASES}/download/v2.8.10/app.zip"/></item>
                <item><enclosure sparkle:version="304.1" url="{RELEASES}/download/v2.8.9/app.zip"/></item>
            </channel></rss>''')
            self.assertEqual(feed_builds(feed), [(305, 0, 0), (304, 1, 0)])

    def test_previous_feed_rejects_upstream_or_missing_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / "appcast.xml"
            for enclosure in ['<enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v1/app.zip"/>', ""]:
                feed.write_text(f"<rss><channel><item>{enclosure}</item></channel></rss>")
                with self.subTest(enclosure=enclosure), self.assertRaises(ValueError):
                    feed_builds(feed)

    def test_generated_feed_must_match_actual_archive_and_version(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "AirIsland-2.8.10-macOS-arm64.zip"
            archive.write_bytes(b"archive bytes")
            feed = Path(directory) / "appcast.xml"
            signature = base64.b64encode(bytes(64)).decode()
            xml = f'''<rss xmlns:sparkle="{SPARKLE[1:-1]}"><channel><item>
                <sparkle:version>305</sparkle:version><sparkle:shortVersionString>2.8.10</sparkle:shortVersionString>
                <enclosure url="{RELEASES}/download/v2.8.10/{archive.name}" length="13" sparkle:edSignature="{signature}"/>
            </item></channel></rss>'''
            feed.write_text(xml)
            self.assertEqual(validate_generated_feed(feed, archive, "2.8.10", "305"), signature)
            for old, new in [('length="13"', 'length="14"'), ('>305<', '>304<'),
                             ('>2.8.10<', '>2.8.9<'), ('sparkle:edSignature="' + signature + '"', ''),
                             ('/download/v2.8.10/', '/download/v2.8.9/'),
                             ('</item>', '<sparkle:channel>beta</sparkle:channel></item>')]:
                feed.write_text(xml.replace(old, new))
                with self.subTest(change=old), self.assertRaises(ValueError):
                    validate_generated_feed(feed, archive, "2.8.10", "305")


if __name__ == "__main__":
    unittest.main()
