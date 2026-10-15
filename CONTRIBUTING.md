# Contributing

Use Flutter 3.41.4 and Dart 3.11.1 as the baseline for this snapshot. Resolve dependencies with `flutter pub get`, then run `flutter analyze` and `flutter test`. Format changed Dart files with `dart format`.

Keep changes focused and describe the user-visible behavior, validation, and any platform limitations. For download or Kotlin changes, include Android/device or desktop testing where possible; module tests alone do not exercise live websites or native execution. Clearly distinguish standalone infrastructure from features connected to `lib/main.dart`.

Bug reports should include the target OS, app/engine versions, reproduction steps, and a redacted error. Use a public example URL you are permitted to download. Do not attach private media, cookies, credentials, signing files, complete personal logs, or local SDK paths.

Before committing, inspect `git diff --cached` and the file list. Keep build outputs, archives, `android/local.properties`, `android/key.properties`, certificates, keystores, `.env` files, private config, and IDE state out of commits. Use a GitHub no-reply address or another deliberately chosen non-personal author identity if you want to keep your email out of public commit metadata. GitHub repository ownership and public activity remain visible.

Contributions to original project files are submitted under the project's MIT License. Third-party components keep their existing licenses.
