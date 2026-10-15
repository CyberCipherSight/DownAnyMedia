/// Central home for user-facing strings.
///
/// Feature spec rule 6: every user-facing string lives in one place, no
/// literals scattered across widgets. This is a plain static map, not a full
/// i18n framework (ponytail: single-locale app, add intl only if translation
/// is ever actually requested).
class AppStrings {
  const AppStrings._();

  // --- Error messages (Feature 3a taxonomy) ---
  static const errInvalidUrl =
      "That doesn't look like a valid link. Check for typos or paste the full URL.";
  static const errUnsupportedSite =
      "This site isn't supported for downloading.";
  static const errVideoUnavailable =
      'This video is private, deleted, or unavailable.';
  static const errGeoBlocked = 'This content is blocked in your region.';
  static const errAgeRestricted =
      "This video is age-restricted and requires sign-in, which this app doesn't support.";
  static const errAuthRequired =
      'This content requires an account login. Only public content can be downloaded.';
  static const errNetwork =
      'Network problem. Check your connection and try again.';
  static const errLiveStream =
      "This is a live/upcoming stream and can't be downloaded yet.";
  static const errFormatUnavailable =
      'No downloadable format was found for this quality. Try a different quality preset.';
  static const errFfmpeg =
      "Conversion failed. The video was downloaded but couldn't be converted or merged.";
  static const errEngine = "The download engine isn't ready.";
  static const errUnknown = 'Something went wrong.';

  static String errStorageFull(String estimate) =>
      'Not enough storage space. Free up at least ~$estimate and retry.';
  static const errPermission =
      "Can't write to the chosen folder. Pick a different folder in Settings.";

  // Platform-disabled (Feature 5f) — generic fallback when no override present.
  static String platformDisabled(String platformLabel) =>
      'Downloads from $platformLabel are currently not supported.';

  // DRM / Spotify (Feature 2b + 3a).
  static const errDrmSpotify =
      'Spotify uses DRM protection and cannot be downloaded directly.';

  // --- Platform warnings (Feature 2b) ---
  static const warnYoutubeMix =
      'This looks like an endless mix or radio — only the first 200 items will be analyzed.';
  static const warnRedditNoAudio =
      'Reddit videos on this device will be video-only (no audio).';
  static const warnPublicOnly = 'Only public posts can be downloaded.';
  static const warnTwitchVod =
      'Twitch VODs can be several hours long — check the duration before downloading.';
  static const warnGeneric =
      'Trying generic extraction — this may not work on all sites.';

  // --- Selection UI (Feature 1b) ---
  static const selectAtLeastOne = 'Select at least one item';
  static const rangeInvalid = 'Enter a valid range within 1..{max}';

  // --- Retry / queue (Feature 3c) ---
  static const connectionRestored = 'Connection restored — resuming downloads';
  static String retryingIn(int seconds, int attempt, int max) =>
      'Retrying in ${seconds}s (attempt $attempt of $max)…';

  // --- Badges ---
  static const badgePrivate = 'Private';
  static const badgeDeleted = 'Deleted';
  static const badgeUnavailable = 'Unavailable';
  static const badgeDownloaded = 'Downloaded';
}
