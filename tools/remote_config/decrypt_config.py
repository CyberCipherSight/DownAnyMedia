#!/usr/bin/env python3
"""Decrypt and pretty-print the live `jadugame` remote config.

The "what is currently live?" sanity check — always run it after pushing.

Usage:
    python3 decrypt_config.py --url URL       # fetch an explicitly chosen URL
    python3 decrypt_config.py --file jadugame # decrypt a local blob instead
Requires: pip install cryptography requests
"""
import argparse
import base64
import json
import os
import sys
import time

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

HERE = os.path.dirname(os.path.abspath(__file__))
SECRET = os.path.join(HERE, "secret.key")


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def load_key():
    if not os.path.exists(SECRET):
        die("secret.key not found — run encrypt_config.py first")
    with open(SECRET) as f:
        key = base64.b64decode(f.read().strip())
    if len(key) != 32:
        die("secret.key must decode to exactly 32 bytes")
    return key


def fetch_blob(local_file, remote_url):
    if local_file:
        with open(local_file) as f:
            return f.read().strip()
    import requests  # imported lazily so --file works without requests
    resp = requests.get(remote_url, params={"v": int(time.time())}, timeout=10)
    resp.raise_for_status()
    return resp.text.strip()


def main():
    ap = argparse.ArgumentParser()
    source = ap.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", help="decrypt a local blob instead of fetching")
    source.add_argument("--url", help="explicit URL of a remote config blob")
    args = ap.parse_args()

    key = load_key()
    raw = base64.b64decode(fetch_blob(args.file, args.url))
    if len(raw) < 12 + 16:
        die("blob too short")
    nonce, cipher_and_tag = raw[:12], raw[12:]
    try:
        plaintext = AESGCM(key).decrypt(nonce, cipher_and_tag, None)
    except Exception as e:  # noqa: BLE001 - any auth/parse failure is fatal here
        die(f"decryption failed (wrong key or tampered blob): {e}")
    print(json.dumps(json.loads(plaintext), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
