# Android release guide

Android is the primary distribution target for DownAnyMedia. Linux and Windows runners remain in the source tree, but this release provides Android APKs only.

## Download and install

Download from the [1.0.0 Android release](https://github.com/CyberCipherSight/DownAnyMedia/releases/tag/v1.0.0). The release contains three signed, standalone APKs. Install one matching your CPU; they are not pieces that need to be installed together.

- **[ARM64 APK](https://github.com/CyberCipherSight/DownAnyMedia/releases/download/v1.0.0/DownAnyMedia-1.0.0-arm64-v8a.apk)**: the usual choice for a modern phone.
- **[ARMv7 APK](https://github.com/CyberCipherSight/DownAnyMedia/releases/download/v1.0.0/DownAnyMedia-1.0.0-armeabi-v7a.apk)**: for a 32-bit ARM device.
- **[x86-64 APK](https://github.com/CyberCipherSight/DownAnyMedia/releases/download/v1.0.0/DownAnyMedia-1.0.0-x86_64.apk)**: used for the emulator test documented below.

The built manifest requires **Android 7.0 / API 24 or later** and targets API 36. To identify a connected device, run `adb shell getprop ro.product.cpu.abi`. Open the downloaded APK and, if Android asks, allow installation from that browser/file manager. Or install from a computer with `adb install path/to/the.apk`.

These releases use a new project-only signing certificate. They cannot update an earlier APK signed with a different key. Android may report a signature mismatch; uninstalling the old app removes its app settings/history, while media already saved in shared Downloads generally remains. Back up anything you need before switching. Future releases must retain this release signing key to support updates.

## Size optimization

The local starting APK was a **280,081,174-byte debug APK** containing four CPU architectures, debug Flutter assets, and native media runtimes. The measured release files are:

| Architecture | Choose for | APK download size | Reduction from original debug APK |
| --- | --- | --- | --- |
| `arm64-v8a` | Most modern Android phones | 64.27 MB | 77.05% |
| `armeabi-v7a` | Older 32-bit ARM devices | 57.05 MB | 79.63% |
| `x86_64` | Intel/AMD emulators and devices | 67.41 MB | 75.93% |

Sizes use decimal MB (1 MB = 1,000,000 bytes). This comparison combines release-mode optimization and architecture splitting; it is not a claim that R8 alone saves 77%. Installed storage is larger because Android and the media engine extract native libraries and runtime packages, and downloads need additional space.

Changes made:

1. Build in Flutter release mode with ahead-of-time Dart compilation and icon tree shaking. No Dart debug kernel or Vulkan validation layer is included.
2. Use `--split-per-abi`; each APK contains only its advertised architecture. Remove the hardcoded four-ABI filter that prevented correct split builds. Legacy x86 is not included because the Flutter runtime targets supported ARM/ARM64/x86-64 architectures.
3. Enable R8 code shrinking and Android resource shrinking. Preserve the Commons Compress ZIP extra-field implementations that are instantiated reflectively; without that rule, the optimized APK opened but failed to unpack its Python/FFmpeg runtime. Preserve the reflected FFmpeg path field as well.
4. Move Dart debug information to private symbol files with `--split-debug-info`. Build from a neutral temporary directory so developer workstation paths do not appear in the published compiled Dart image.
5. Keep Python, FFmpeg, yt-dlp, and supported audio/video functionality. These native engines dominate the remaining download size. This release does not remove conversion features or depend on a project-hosted conversion server.

See [Flutter's Android release guide](https://docs.flutter.dev/deployment/android) and [Android's R8 documentation](https://developer.android.com/topic/performance/app-optimization/enable-app-optimization) for the build mechanisms.

## Actual emulator checks

The release x86-64 APK was installed and run in a fresh Android 16 emulator using the installed `android-36.1` x86-64 image, a 1080 x 2400 display, and no signed-in personal account. The installed APK is the same x86-64 file attached to this release.

| Check | Observed result |
| --- | --- |
| Install, launch, render, and initial engine unpack | Passed after the targeted R8 fix |
| Bundled FFmpeg executable probe | Passed; reports FFmpeg 7.1.1 |
| Android VIEW intent containing a media URL | Accepted; identified as a single media item |
| Audio download/conversion | Passed; a six-second synthetic MP4 became a playable-format MP3 with a measured duration of 6.014 seconds |
| Video download | Passed; six-second MP4 with H.264 video and AAC audio, duration 6.000 seconds |
| Publishing completed files | Both files appeared in `Download/DownAnyMedia` and in app history |
| Settings and About/license screen | Opened successfully; project and dependency license access is available |
| Dart validation | `flutter analyze` and all 106 existing/module tests passed |
| APK structure/signing/privacy | One intended ABI per APK; signing verified; certificate contains project name only; checked for local personal build paths and old account-specific config URL |

The test clip was generated locally from an FFmpeg test pattern and sine tone. It was served through a local HTTP server forwarded with `adb reverse`, then downloaded and converted by the actual app. The resulting files were pulled from shared Downloads and inspected with `ffprobe`. No download history or successful state was fabricated or injected.

This verifies local generic-media intake, engine execution, MP3 conversion, video saving, MediaStore publishing, and UI behavior. It does not establish YouTube/social-site compatibility, DRM access, playlist reliability across websites, background survival on every Android vendor, or operation on physical ARM hardware. ARM64 and ARMv7 APKs were built, structurally checked, and signature-verified; the emulator execution test used x86-64. This is an initial Android release, so device-specific reports are welcome.

## Screenshots

[Home](screenshots/android-home.png), [completed video and history](screenshots/android-completed.png), [working engine and versions](screenshots/android-engine.png), and [Settings](screenshots/android-settings.png) are genuine captures of the release app. Android's demo status bar shows 10:00; no app content was composited or retouched. Google test ads are visible. Demo filenames and timestamps belong to synthetic test media.

The home screenshot has no URL, so its Download button is correctly disabled. The engine screenshot reports the actual bundled FFmpeg version; yt-dlp can initially show `Unknown` before its updater records a version. The completed screenshot shows a real saved video and history entry. The Settings screenshot was captured in Video mode, where the audio-only controls are intentionally hidden.

## Build the same configuration

Use Flutter 3.41.4 / Dart 3.11.1, Android SDK 36, NDK 28.2.13676358, and a compatible JDK (the release build used JDK 21). The Gradle wrapper selects Gradle 8.14; the project uses Android Gradle Plugin 8.11.1, Kotlin 2.2.20, and `youtubedl-android` 0.18.1.

Create your own keystore and private `android/key.properties` containing `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`, as described in the [Flutter signing guide](https://docs.flutter.dev/deployment/android#sign-the-app). Use a project-only certificate subject if you do not want personal identity fields in the resulting APK. Never commit the keystore, password file, or private symbols.

```sh
flutter pub get
flutter analyze
flutter test
python3 tools/android/build_release.py --version 1.0.0 --build-number 1
```

The helper copies version-controlled source and non-ignored new source files into a neutral temporary directory, resolves the private keystore location, and runs:

```sh
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64,android-x64 \
  --split-debug-info=<private-symbol-directory> \
  --build-name 1.0.0 --build-number 1
```

Outputs and checksums are written to ignored `release-artifacts/v1.0.0/`. Debug symbols stay in ignored `.release-signing/symbols/`. The helper does not upload anything. Independently built APK hashes may differ because of signing keys, paths, toolchains, and build timestamps; this is a repeatable build recipe, not a byte-for-byte reproducibility guarantee.

## Checksums and certificate

Compare downloads with the release's `SHA256SUMS.txt` (for example `sha256sum -c SHA256SUMS.txt` in a folder containing all assets).

```text
12d7c3e7cfc57c8d09afefd957915ec121ec5d5952ce7cb7d22c72440dd05121  DownAnyMedia-1.0.0-arm64-v8a.apk
6dfaac144b6ffade805be653b1a3232f2c5fdc6eba5eec0e689d72064f1fffe1  DownAnyMedia-1.0.0-armeabi-v7a.apk
aadb7b1b249c92d1971afc3faac8f21de980367d938d3d8083652fd3c8462b04  DownAnyMedia-1.0.0-x86_64.apk
```

The public APK signing certificate uses `CN=DownAnyMedia, O=DownAnyMedia` and SHA-256 fingerprint:

```text
1de44924f76209f128bb2f784e02c8f356465183a32350ec7ff5950881728c10
```

The private key is retained locally and is not a release asset. The source snapshot, build settings, screenshots, exact engine Java/Kotlin source jars and metadata, size report, and checksums are public. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for the GPL-enabled engine/native components and their source/build links; original project files remain MIT licensed. See [PRIVACY.md](../PRIVACY.md) for runtime network behavior, test advertising, local history, and merged Android permissions.
