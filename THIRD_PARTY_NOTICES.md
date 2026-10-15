# Third-party components

The MIT License at the repository root applies to original DownAnyMedia project files. It does not replace licenses or terms attached to dependencies, Flutter tooling/templates, advertising SDKs, media engines, or downloaded content.

Direct Dart dependencies are declared in `pubspec.yaml`; exact resolved Dart packages and hashes are recorded in `pubspec.lock`. Android native versions are declared in `android/app/build.gradle.kts`, including `youtubedl-android` library and FFmpeg artifacts at version 0.18.1. Gradle resolves additional transitive dependencies.

| Component | Source / license information |
| --- | --- |
| Flutter and Dart | [Flutter licenses](https://github.com/flutter/flutter/blob/master/LICENSE), [Dart license](https://github.com/dart-lang/sdk/blob/main/LICENSE) |
| yt-dlp | [Source and license](https://github.com/yt-dlp/yt-dlp); the main source uses the Unlicense, while packaged executables can include components under other licenses |
| youtubedl-android | [Upstream repository and bundled-component notices](https://github.com/JunkFood02/youtubedl-android) |
| FFmpeg | [Official licensing information](https://ffmpeg.org/legal.html); licensing depends on the exact build and enabled components |
| Google Mobile Ads Flutter plugin and Android SDK | [Plugin source](https://github.com/googleads/googleads-mobile-flutter), [SDK terms](https://developers.google.com/admob/android/terms) |
| Other pub packages | The corresponding package's LICENSE, resolved through `pubspec.lock` and Flutter's generated license registry |
| Python developer tools | Optional `cryptography` and `requests` dependencies; see their upstream distributions' licenses |

This source repository does not distribute APKs, desktop tool executables, or a vendored dependency tree. Building an APK fetches and bundles native runtimes and media tools. Before redistributing binaries, inspect the licenses and build options of the exact resolved artifacts, preserve required notices, and provide corresponding source/build information where required. The project's MIT license alone does not cover every component of a compiled distribution. This document is an inventory and does not certify binary distribution compliance.
