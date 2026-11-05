#!/usr/bin/env python3
"""Prepare a signed stable update from an already built AirIsland.app.

This does not publish a release, edit the repository feed, or export private keys.
The key lives in the macOS login Keychain under the Sparkle account AirIsland.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RELEASES = "https://github.com/potato0620/AirIsSland/releases"
FEED_URL = "https://raw.githubusercontent.com/potato0620/AirIsSland/main/updater/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
KEY_ACCOUNT = "AirIsland"


def build_number(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ValueError(f"Invalid build number: {value}")
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def feed_builds(path: Path) -> list[tuple[int, int, int]]:
    channel = ET.parse(path).getroot().find("channel")
    if channel is None:
        raise ValueError("The previous feed has no channel")
    builds = []
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        if enclosure is None or not enclosure.get("url", "").startswith(RELEASES + "/download/"):
            raise ValueError("The previous feed contains an update outside AirIsland releases")
        version = item.findtext(SPARKLE + "version") or enclosure.get(SPARKLE + "version", "")
        builds.append(build_number(version))
    return builds


def validate_app(info: dict, expected_key: str, previous_builds: list[tuple[int, int, int]]) -> tuple[str, str]:
    if info.get("CFBundleIdentifier") != "theboringteam.boringnotch":
        raise ValueError("The bundle identifier must retain the existing AirIsland identity")
    if info.get("SUFeedURL") != FEED_URL or info.get("SUPublicEDKey") != expected_key:
        raise ValueError("The built app must contain the AirIsland feed and signing public key")
    for key in ("SUEnableInstallerLauncherService", "SUVerifyUpdateBeforeExtraction"):
        if info.get(key) is not True:
            raise ValueError(f"The built app must enable {key}")
    for key in ("SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates"):
        if info.get(key) is not False:
            raise ValueError(f"The built app must disable {key} for manual updates")
    version = str(info.get("CFBundleShortVersionString", ""))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Only stable major.minor.patch versions are supported")
    build = str(info.get("CFBundleVersion", ""))
    parsed = build_number(build)
    if previous_builds and parsed <= max(previous_builds):
        raise ValueError("The build number must exceed every previously published build")
    return version, build


def validate_generated_feed(path: Path, archive: Path, version: str, build: str) -> str:
    items = ET.parse(path).getroot().findall("channel/item")
    if len(items) != 1:
        raise ValueError("The generated feed must contain exactly this release")
    item = items[0]
    if item.findtext(SPARKLE + "version") != build or item.findtext(SPARKLE + "shortVersionString") != version:
        raise ValueError("The generated feed version differs from the built app")
    if item.find(SPARKLE + "channel") is not None:
        raise ValueError("Stable updates must use the default channel")
    enclosure = item.find("enclosure")
    expected_url = f"{RELEASES}/download/v{version}/{archive.name}"
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("The generated download URL differs from the release asset")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("The generated archive size is incorrect")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("The generated update is missing a valid Ed25519 signature")
    return signature


def prepare(app: Path, output: Path, sparkle_bin: Path, notes: Path, previous_feed: Path) -> None:
    app, output, sparkle_bin = app.resolve(), output.resolve(), sparkle_bin.resolve()
    if output.is_relative_to(app):
        raise ValueError("The output directory must be outside the signed app bundle")
    if output.exists():
        raise ValueError("The output directory already exists; use a new directory")
    for tool in ("generate_keys", "generate_appcast", "sign_update"):
        if not (sparkle_bin / tool).is_file():
            raise ValueError(f"Missing Sparkle tool: {tool}")
    notes_text = notes.read_text(encoding="utf-8")
    if not notes_text.strip():
        raise ValueError("Release notes must not be empty")
    with (ROOT / "AirIsland/Info.plist").open("rb") as stream:
        expected_key = plistlib.load(stream)["SUPublicEDKey"]
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version, build = validate_app(info, expected_key, feed_builds(previous_feed))
    public_key = subprocess.check_output(
        [str(sparkle_bin / "generate_keys"), "--account", KEY_ACCOUNT, "-p"], text=True
    ).strip()
    if public_key != expected_key:
        raise ValueError("The AirIsland Keychain signing key does not match the app public key")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    # One archive per feed. Never mix old upstream packages or delta files in.
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".airisland-update-", dir=output.parent) as temp:
        staging = Path(temp) / "release"
        staging.mkdir()
        archive = staging / f"AirIsland-{version}-macOS-arm64.zip"
        architectures = subprocess.check_output(
            ["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/AirIsland")], text=True
        ).split()
        if architectures != ["arm64"]:
            raise ValueError("This release package is for Apple Silicon only")
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
        # Plain text release notes avoid executing or fetching remote content.
        release_notes = archive.with_suffix(".txt")
        release_notes.write_text(notes_text, encoding="utf-8")
        feed = staging / "appcast.xml"
        subprocess.run([
            str(sparkle_bin / "generate_appcast"), "--account", KEY_ACCOUNT,
            "--maximum-deltas", "0", "--maximum-versions", "1", "--embed-release-notes",
            "--link", RELEASES, "--download-url-prefix", f"{RELEASES}/download/v{version}/",
            "-o", str(feed), str(staging),
        ], check=True)
        signature = validate_generated_feed(feed, archive, version, build)
        subprocess.run([
            str(sparkle_bin / "sign_update"), "--account", KEY_ACCOUNT,
            "--verify", str(archive), signature,
        ], check=True)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (staging / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
        release_notes.unlink()  # Notes are embedded in the feed.
        shutil.move(str(staging), str(output))
    print(f"Prepared AirIsland {version} ({build}) in {output}")
    print("Upload the ZIP to its matching GitHub Release and publish the release first.")
    print("Only then commit and push appcast.xml to updater/appcast.xml on main.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sparkle-bin", type=Path, required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--previous-feed", type=Path, default=ROOT / "updater/appcast.xml")
    args = parser.parse_args()
    try:
        prepare(args.app, args.output, args.sparkle_bin, args.notes, args.previous_feed)
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Could not prepare update: {error}\n")


if __name__ == "__main__":
    main()
