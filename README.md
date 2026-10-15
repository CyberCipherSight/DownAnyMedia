# DownAnyMedia

A Flutter app for downloading MP3 audio and video with yt-dlp and FFmpeg. The project includes Android, Linux, and Windows runners, with local download history and a sequential playlist queue.

## Features

- Paste a media URL or receive a link through Android's share sheet.
- Analyze single items and playlists before downloading.
- Choose MP3 quality or a preferred video quality; video downloads try fallback formats when necessary.
- Pause the playlist queue between items, resume it, retry failures, or cancel downloads.
- Remember the queue, history, output folder, quality, and theme on the device.
- Optionally embed audio metadata and artwork, number playlist files, and clean tracking parameters from URLs.
- Inspect engine status, versions, and Android FFmpeg diagnostics.

Support depends on the installed yt-dlp version, the source website, available formats, and device capabilities. There is no guarantee that every website or playlist will work. This app does not implement DRM decryption. Download only content you own or have permission to save.

## Get started

Use Flutter **3.41.4 / Dart 3.11.1** as the reproducible starting point for this source snapshot. `pubspec.yaml` requires Dart `^3.11.1`. Install the platform toolchain for your target, then run from the repository root:

```sh
flutter pub get
flutter analyze
flutter test
```

### Android

Install the Android SDK and a JDK compatible with Android Gradle Plugin 8.11.1 (Java 17 or newer). The Kotlin sources target Java 17. `flutter doctor -v` reports missing tooling.

```sh
flutter build apk --debug
# Or run on an attached device:
flutter run -d <device-id>
```

The debug APK is generated under `build/app/outputs/flutter-apk/`. Flutter creates machine-specific Gradle wrapper and SDK configuration files as needed; these are excluded from version control. Android dependencies download yt-dlp, Python, and FFmpeg through `youtubedl-android` **0.18.1**. Android saves completed files through MediaStore under the shared Downloads directory (`Download/DownAnyMedia`, with playlist subfolders).

Release signing is intentionally unconfigured. To build your own signed release, create a private `android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. `storeFile` is resolved relative to `android/`. Never commit that file or a keystore. An optional `admobApplicationId` overrides the public Google test application ID. No signing keys or store credentials are provided.

### Linux

Install Flutter's Linux desktop build prerequisites, plus `yt-dlp` and `ffmpeg` on `PATH`.

```sh
flutter run -d linux
flutter build linux --release
```

### Windows

Use a Windows Flutter environment with Visual Studio's Desktop development with C++ workload. Install `yt-dlp.exe` and `ffmpeg.exe` on `PATH`.

```powershell
flutter run -d windows
flutter build windows --release
```

Desktop builds also search for tools next to the application in `bin/`, `bin/linux/`, and `bin/windows/`, then fall back to `PATH`. This repository contains no bundled desktop executables. Windows compilation and device download behavior must be checked on the corresponding platform; unit tests do not establish that they work.

## How it works

1. The UI passes the URL to yt-dlp for metadata and playlist analysis. Analysis itself contacts the source website.
2. For audio, yt-dlp downloads the best available audio and FFmpeg converts it to MP3. For video, yt-dlp selects streams and FFmpeg merges them when needed; fallback selectors may produce a lower quality or a different container.
3. Android delegates execution to Kotlin through a Flutter method channel and uses a foreground service for progress notifications. Desktop launches external processes with argument lists.
4. Finished files stay on the device. History stores file paths or Android content URIs; removing a history entry does not remove the downloaded file.

Most running application logic currently lives in `lib/main.dart`. Additional service modules and tests are present, but several are **not connected to the running UI**. In particular, the remote configuration service and config-driven interstitial controller are standalone infrastructure; publishing a configuration does not currently change the running app. See [architecture.md](architecture.md) for the exact boundaries.

## Ads, network access, and privacy

Android initializes Google Mobile Ads and uses Google's public **test** IDs for a banner and an optional rewarded ad. Earning a reward hides ads for one hour. Test ads still contact Google's services. Desktop does not initialize the ads SDK.

There is no project-operated download server or account system in this source snapshot. yt-dlp contacts source websites, Android can request engine updates, and Google Mobile Ads contacts its services. URLs, file paths, queue state, and history are stored locally and can appear in diagnostics. See [PRIVACY.md](PRIVACY.md) for details.

Remote configuration has **no default endpoint**. Its optional AES-GCM format, build settings, placeholder key, cache behavior, and limitations are openly documented in [tools/remote_config/README.md](tools/remote_config/README.md). An embedded symmetric key is recoverable and cannot establish trustworthy configuration signing.

## Contributing and licensing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for development and bug reports. See [SECURITY.md](SECURITY.md) for handling sensitive reports.

Original project source is available under the [MIT License](LICENSE), using a collective contributor attribution without a personal name or email. Dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), particularly before distributing Android packages or bundled media tools.
