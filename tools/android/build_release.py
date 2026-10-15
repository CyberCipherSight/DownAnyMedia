#!/usr/bin/env python3
"""Build signed, per-ABI APKs in a neutral temporary directory.

Requires Flutter, Git, an Android toolchain, and private android/key.properties.
No signing material or debug symbols are published by this script.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build-number", default="1")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    signing = root / "android/key.properties"
    if not signing.is_file():
        parser.error("Create private android/key.properties first; see docs/ANDROID.md")
    signing_text = signing.read_text()
    lines = []
    for line in signing_text.splitlines():
        if line.strip().startswith("storeFile="):
            value = line.split("=", 1)[1].strip()
            key = Path(value).expanduser()
            if not key.is_absolute():
                key = root / "android" / key
            if not key.is_file():
                parser.error("The configured private keystore does not exist")
            line = "storeFile=" + key.resolve().as_posix()
        lines.append(line)
    output = root / "release-artifacts" / ("v" + args.version)
    output.mkdir(parents=True, exist_ok=True)
    symbols = root / ".release-signing" / "symbols" / ("v" + args.version)
    symbols.mkdir(parents=True, exist_ok=True)
    names = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
    ).decode().strip("\0").split("\0")
    with tempfile.TemporaryDirectory(prefix="downanymedia-build-") as temp:
        stage = Path(temp)
        for name in names:
            src = root / name
            if not src.is_file() or src.is_symlink():
                continue
            dest = stage / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
        private = stage / "android/key.properties"
        private.write_text("\n".join(lines) + "\n")
        private.chmod(0o600)
        subprocess.run([
            "flutter", "build", "apk", "--release", "--split-per-abi",
            "--target-platform", "android-arm,android-arm64,android-x64",
            "--split-debug-info=" + str(symbols),
            "--build-name", args.version, "--build-number", args.build_number,
        ], cwd=stage, check=True)
        records = []
        for abi in ["arm64-v8a", "armeabi-v7a", "x86_64"]:
            src = stage / "build/app/outputs/flutter-apk" / ("app-" + abi + "-release.apk")
            dest = output / ("DownAnyMedia-" + args.version + "-" + abi + ".apk")
            shutil.copyfile(src, dest)
            records.append({"file": dest.name, "bytes": dest.stat().st_size,
                            "sha256": hashlib.sha256(dest.read_bytes()).hexdigest()})
    (output / "SHA256SUMS.txt").write_text("".join(
        row["sha256"] + "  " + row["file"] + "\n" for row in records
    ))
    (output / "apk-sizes.json").write_text(json.dumps(records, indent=2) + "\n")
    for row in records:
        print(row["file"], str(row["bytes"]) + " bytes")
    print("Artifacts:", output)
    print("Keep the signing key and debug symbols private; audit APKs before publishing.")


if __name__ == "__main__":
    main()
