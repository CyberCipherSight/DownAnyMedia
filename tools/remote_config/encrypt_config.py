#!/usr/bin/env python3
"""Encrypt config.json -> `jadugame` blob for the DownAnyMedia remote config.

HONESTY NOTE: the decryption key ships inside the APK, so this is OBFUSCATION,
not real security. Anyone who decompiles the app can extract the key and
read/forge the config. Do not build anything security-critical on top of it.

Wire format (matches the Dart `encrypt` package's AES-GCM):
    base64( nonce(12) || ciphertext || gcmTag(16) )   on a single line.

Usage:
    python3 encrypt_config.py                 # writes ./jadugame
    python3 encrypt_config.py --push CLONE     # also commit+push into a local
                                               # clone of the chosen configuration repo
Requires: pip install cryptography
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "config.json")
SECRET = os.path.join(HERE, "secret.key")
LAST_VERSION = os.path.join(HERE, ".last_version")
OUT = os.path.join(HERE, "jadugame")

# Must exactly mirror MediaPlatform (minus `unknown`) in url_classifier.dart.
PLATFORMS = [
    "youtube", "reddit", "facebook", "instagram", "twitter", "tiktok",
    "soundcloud", "vimeo", "twitch", "spotify", "generic",
]
AD_ID_RE = re.compile(r"^ca-app-pub-\S+$")


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def load_key():
    """secret.key holds the 32-byte AES key as one base64 line. Generated on
    first run if absent."""
    if not os.path.exists(SECRET):
        key = os.urandom(32)
        with open(SECRET, "w") as f:
            f.write(base64.b64encode(key).decode())
        print(f"generated new secret.key ({SECRET}) — keep it private!",
              file=sys.stderr)
        return key
    with open(SECRET) as f:
        key = base64.b64decode(f.read().strip())
    if len(key) != 32:
        die("secret.key must decode to exactly 32 bytes")
    return key


def validate(cfg):
    if "configVersion" not in cfg or not isinstance(cfg["configVersion"], int):
        die("configVersion must be an integer")
    platforms = cfg.get("platforms", {})
    missing = [p for p in PLATFORMS if p not in platforms]
    if missing:
        die(f"platforms missing keys: {', '.join(missing)} "
            "(every platform must be present so none silently defaults)")
    extra = [p for p in platforms if p not in PLATFORMS]
    if extra:
        die(f"platforms has unknown keys: {', '.join(extra)}")
    ads = cfg.get("ads", {})
    for fmt in ("banner", "interstitial", "rewarded"):
        block = ads.get(fmt, {})
        uid = block.get("unitId", "")
        if uid and not AD_ID_RE.match(uid):
            die(f"ads.{fmt}.unitId must be a ca-app-pub- id or empty, got {uid!r}")
    n = ads.get("interstitial", {}).get("showAfterEveryNDownloads", 0)
    if not isinstance(n, int) or n < 0:
        die("ads.interstitial.showAfterEveryNDownloads must be an int >= 0")


def check_version(cfg):
    version = cfg["configVersion"]
    last = -1
    if os.path.exists(LAST_VERSION):
        with open(LAST_VERSION) as f:
            last = int(f.read().strip() or "-1")
    if version <= last:
        die(f"configVersion {version} must be greater than last encrypted "
            f"version {last} (bump it)")
    return version


def print_key_parts(key):
    """Print two 32-byte XOR parts (partA ^ partB == key) as Dart int lists,
    ready to paste into RemoteConfigService._assembleKey."""
    part_b = os.urandom(32)
    part_a = bytes(k ^ b for k, b in zip(key, part_b))
    print("\n// Paste into RemoteConfigService._assembleKey (parts XOR to key):",
          file=sys.stderr)
    print(f"final partA = <int>{list(part_a)};", file=sys.stderr)
    print(f"final partB = <int>{list(part_b)};", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--push", metavar="CLONE",
                    help="path to a local clone of the chosen configuration repo")
    ap.add_argument("--print-key-parts", action="store_true",
                    help="also print Dart XOR key parts to stderr")
    args = ap.parse_args()

    if not os.path.exists(CONFIG):
        die(f"{CONFIG} not found — create it from config.example.json")
    with open(CONFIG) as f:
        cfg = json.load(f)

    validate(cfg)
    version = check_version(cfg)
    key = load_key()

    plaintext = json.dumps(cfg, separators=(",", ":")).encode()
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext, None)  # ct || tag(16)
    blob = base64.b64encode(nonce + ct).decode()

    with open(OUT, "w") as f:
        f.write(blob)
    with open(LAST_VERSION, "w") as f:
        f.write(str(version))
    print(blob)

    if args.print_key_parts:
        print_key_parts(key)

    if args.push:
        dest = os.path.join(args.push, "jadugame")
        with open(dest, "w") as f:
            f.write(blob)
        subprocess.run(["git", "-C", args.push, "add", "jadugame"], check=True)
        subprocess.run(["git", "-C", args.push, "commit", "-m", "update assets"],
                       check=True)
        subprocess.run(["git", "-C", args.push, "push"], check=True)
        print(f"pushed v{version} to {args.push}", file=sys.stderr)


if __name__ == "__main__":
    main()
