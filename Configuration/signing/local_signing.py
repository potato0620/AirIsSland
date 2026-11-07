#!/usr/bin/env python3
"""Stable, certificate-pinned identity for local AirIsland development builds.

This never adds a trusted root or edits TCC. It is not Developer ID distribution.
Private key material is imported into Keychain and removed from the temporary files.
"""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import tempfile

STATE = Path.home() / "Library/Application Support/AirIsland/LocalSigning"
APP_ID = "theboringteam.boringnotch"
HELPER_ID = APP_ID + ".BoringNotchXPCHelper"


def run(args):
    try:
        result = subprocess.run([str(a) for a in args], capture_output=True, timeout=120)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{Path(args[0]).name}: timed out (arguments withheld)") from None
    if result.returncode:
        # Do not include argv: import commands contain temporary key passwords.
        raise RuntimeError(f"{Path(args[0]).name}: {result.stderr.decode(errors='replace')[-3000:]}")
    return result.stdout


def create_identity(directory, keychain):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / ".initialization.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _create_identity(directory, keychain)


def _create_identity(directory, keychain):
    if (directory / "identity.json").exists():
        return load_identity(directory)
    if (directory / "certificate.pem").exists():
        raise RuntimeError("Incomplete local identity; recover its certificate/private key rather than regenerate it.")
    with tempfile.TemporaryDirectory(prefix="airisland-signing-") as tmp:
        tmp = Path(tmp)
        config = tmp / "openssl.cnf"
        config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = codesign
[subject]
CN = AirIsland Local Development
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
""")
        key, cert, bundle = (tmp / name for name in ("key.pem", "cert.pem", "identity.p12"))
        run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-days", "3650",
             "-config", config, "-keyout", key, "-out", cert])
        key.chmod(0o600)
        password = secrets.token_urlsafe(32)
        # Explicit legacy PBE is required by macOS PKCS#12 import, even with OpenSSL 3.
        run(["openssl", "pkcs12", "-export", "-inkey", key, "-in", cert, "-out", bundle,
             "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
             "-passout", "pass:" + password])
        bundle.chmod(0o600)
        run(["/usr/bin/security", "import", bundle, "-k", keychain, "-P", password,
             "-T", "/usr/bin/codesign"])
        public = cert.read_bytes()
        fingerprint = hashlib.sha1(run(["openssl", "x509", "-in", cert, "-outform", "DER"])).hexdigest()
        (directory / "certificate.pem").write_bytes(public)
        state = {"version": 1, "fingerprint": fingerprint, "keychain": str(Path(keychain).resolve())}
        path = directory / "identity.json"
        path.write_text(json.dumps(state, indent=2) + "\n")
        path.chmod(0o600)
        return state


def load_identity(directory):
    directory = Path(directory)
    path = directory / "identity.json"
    if not path.exists():
        raise RuntimeError("Local signing identity is not initialized. Run local_signing.py init once.")
    state = json.loads(path.read_text())
    if state.get("version") != 1 or not re.fullmatch(r"[a-f0-9]{40}", state.get("fingerprint", "")):
        raise RuntimeError("Invalid local signing identity configuration; refusing to replace it.")
    fingerprint = hashlib.sha1(run(["openssl", "x509", "-in", directory / "certificate.pem",
                                   "-outform", "DER"])).hexdigest()
    if fingerprint != state["fingerprint"] or not Path(state["keychain"]).is_file():
        raise RuntimeError("The original local signing identity is missing or changed; restore it, do not regenerate it.")
    return state


def requirement(identifier, fingerprint):
    if identifier not in (APP_ID, HELPER_ID):
        raise RuntimeError("Refusing to sign a bundle outside the AirIsland app/helper identities.")
    return f'designated => identifier "{identifier}" and certificate leaf = H"{fingerprint}"'


def bundle_identifier(path):
    with (path / "Contents/Info.plist").open("rb") as stream:
        return plistlib.load(stream)["CFBundleIdentifier"]


def require_private_key(state):
    identities = run(["/usr/bin/security", "find-identity", "-p", "codesigning", state["keychain"]])
    if state["fingerprint"] not in identities.decode().lower():
        raise RuntimeError("The original signing private key is unavailable; refusing to change identity.")


def sign_app(path, state):
    path = Path(path).resolve()
    if path == Path("/Applications/AirIsland.app"):
        raise RuntimeError("Sign the build output, then quit and replace the installed app.")
    if bundle_identifier(path) != APP_ID:
        raise RuntimeError("Expected an AirIsland application bundle.")
    # Preflight before changing any nested signature. Never silently use ad-hoc signing.
    require_private_key(state)
    helpers = list((path / "Contents/XPCServices").glob("AirIslandHelper.xpc"))
    for helper in helpers:
        if bundle_identifier(helper) != HELPER_ID:
            raise RuntimeError("Unexpected AirIslandHelper identity.")
    for code in helpers + [path]:
        identifier = bundle_identifier(code)
        run(["/usr/bin/codesign", "--force", "--sign", state["fingerprint"],
             "--keychain", state["keychain"], "--timestamp=none",
             "--preserve-metadata=identifier,entitlements,flags",
             "--requirements", "=" + requirement(identifier, state["fingerprint"]), code])
        run(["/usr/bin/codesign", "--verify", "--strict", code])
        run(["/usr/bin/codesign", "--verify", "-R",
             "=" + requirement(identifier, state["fingerprint"]).removeprefix("designated => "), code])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", path])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["init", "identity", "sign"])
    parser.add_argument("--state-dir", type=Path, default=STATE)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    if args.command == "init":
        keychain = run(["/usr/bin/security", "default-keychain", "-d", "user"]).decode().strip().strip('"')
        state = create_identity(args.state_dir, keychain)
    else:
        state = load_identity(args.state_dir)
    if args.command == "sign":
        if not args.app:
            parser.error("sign requires --app")
        sign_app(args.app, state)
    else:
        require_private_key(state)
    print(state["fingerprint"])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        raise SystemExit(str(error))
