# Third-party components

The MIT License at the repository root applies to original DownAnyMedia project files. It does not replace licenses or terms attached to dependencies, Flutter tooling/templates, advertising SDKs, media engines, or downloaded content.

Direct Dart dependencies are declared in `pubspec.yaml`; exact resolved Dart packages and hashes are recorded in `pubspec.lock`. Android native versions are declared in `android/app/build.gradle.kts`, including `youtubedl-android` library and FFmpeg artifacts at version 0.18.1. Gradle resolves additional transitive dependencies.

| Component | Source / license information |
| --- | --- |
| Flutter and Dart | [Flutter licenses](https://github.com/flutter/flutter/blob/master/LICENSE), [Dart license](https://github.com/dart-lang/sdk/blob/main/LICENSE) |
| yt-dlp | [Source and license](https://github.com/yt-dlp/yt-dlp); the main source uses the Unlicense, while packaged executables can include components under other licenses |
| youtubedl-android | Version 0.18.1 is published under **GPL-3.0**; see [exact Maven metadata](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/library/0.18.1/library-0.18.1.pom), [published sources](https://repo.maven.apache.org/maven2/io/github/junkfood02/youtubedl-android/), and [upstream repository](https://github.com/JunkFood02/youtubedl-android) |
| FFmpeg | This APK's upstream native build enables `--enable-gpl --enable-version3`; see [official licensing information](https://ffmpeg.org/legal.html) and the upstream build recipes. This is a GPL-enabled build, not an LGPL-only claim. |
| Google Mobile Ads Flutter plugin and Android SDK | [Plugin source](https://github.com/googleads/googleads-mobile-flutter), [SDK terms](https://developers.google.com/admob/android/terms) |
| Other pub packages | The corresponding package's LICENSE, resolved through `pubspec.lock` and Flutter's generated license registry |
| Python developer tools | Optional `cryptography` and `requests` dependencies; see their upstream distributions' licenses |

APKs are distributed as GitHub Release assets rather than committed build files. The Git repository does not contain desktop tool executables or a vendored dependency tree. Building an APK fetches and bundles native runtimes and media tools. The Android About dialog exposes Flutter dependency licenses, original project MIT terms, and the GPLv3 text in `licenses/GPL-3.0.txt`. Release assets also include the exact published Java/Kotlin engine source jars and metadata; those jars alone are not the full source of every native codec/runtime. Native build recipes are documented upstream in [BUILD_FFMPEG.md](https://github.com/JunkFood02/youtubedl-android/blob/master/BUILD_FFMPEG.md) and [BUILD_PYTHON.md](https://github.com/JunkFood02/youtubedl-android/blob/master/BUILD_PYTHON.md), using [Termux packages](https://github.com/termux/termux-packages). Before redistributing binaries, inspect the licenses and build options of the exact resolved artifacts, preserve required notices, and provide corresponding source/build information where required. The project's MIT license alone does not cover every component of a compiled distribution. This document is an inventory and does not certify binary distribution compliance.
