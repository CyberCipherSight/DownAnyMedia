# Privacy and network behavior

This document describes this source snapshot. Custom builds and externally installed tools can behave differently.

## Data kept on the device

The app stores settings, output folder paths, queue entries and source URLs, download titles, file paths/content URIs, history, and the rewarded-ad expiry time in local SharedPreferences. Preferences are not encrypted by this project. Downloaded media is saved to the selected desktop folder or Android shared Downloads; files in shared storage may be accessible to other apps or device users.

Runtime diagnostics can include source URLs, media titles, engine output, errors, and device paths. Review and redact diagnostics before sharing them in an issue. The standalone `AppLog` module is not wired into the running UI. There is no automatic project-maintainer log upload implemented in the app.

Deleting a history entry does not delete the file. Clearing app data removes its local preferences, but shared Downloads may remain. Operating system backups and third-party tools have their own behavior.

## Network connections

| Connection | When and why |
| --- | --- |
| Source website, media hosts, and CDNs | yt-dlp metadata analysis and downloads; entering a URL can trigger analysis before pressing Download |
| Engine update infrastructure | Android attempts a stable yt-dlp update before downloads; endpoints are controlled by the upstream engine library |
| Google Mobile Ads services | Android SDK initialization, banner loading, and optional rewarded ads; public test IDs do not make these requests offline |
| Optional remote configuration URL | Only if the standalone service is explicitly integrated and configured; no endpoint is supplied by default |

This project does not implement a user account system, project-operated download proxy, or a dedicated analytics/crash-reporting SDK. This does not imply third parties receive no data: source sites and advertising services can receive network/device information under their own policies. See [Google Mobile Ads data disclosure documentation](https://developers.google.com/admob/android/privacy/play-data-disclosure) and [Google's Privacy Policy](https://policies.google.com/privacy).

The optional remote-config cache stores decrypted JSON in SharedPreferences. Never put private API credentials, personal details, or payment/license authorization in configuration distributed to client devices.

## Android permissions

- Internet and network state support engine, download, and advertising requests.
- Foreground service/data sync support active download notifications.
- Notification permission is requested where Android requires it.
- Legacy external-storage write permission is declared only through Android API 28.
- Share/link intents allow explicitly supplied text or URLs from other apps.

The app reads the clipboard when the user chooses Paste. Review the source and your chosen dependency versions when assessing a custom distribution.
