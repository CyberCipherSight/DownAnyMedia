import '../app_strings.dart';

/// Cheap, instant, process-free URL classification (Feature 2a).
///
/// Runs BEFORE yt-dlp is ever spawned so obviously-invalid or unsupported
/// input gets inline feedback in <50 ms. This also carries the [MediaPlatform]
/// enum used by remote-config platform gating (Feature 5f).
enum MediaPlatform {
  youtube,
  reddit,
  facebook,
  instagram,
  twitter,
  tiktok,
  soundcloud,
  vimeo,
  twitch,
  spotify,
  generic,
  unknown;

  /// Human label for messages ("Downloads from YouTube are…").
  String get label => switch (this) {
    youtube => 'YouTube',
    reddit => 'Reddit',
    facebook => 'Facebook',
    instagram => 'Instagram',
    twitter => 'Twitter/X',
    tiktok => 'TikTok',
    soundcloud => 'SoundCloud',
    vimeo => 'Vimeo',
    twitch => 'Twitch',
    spotify => 'Spotify',
    generic => 'this site',
    unknown => 'this link',
  };
}

enum UrlKind { single, playlist, channel, profile, ambiguous }

class UrlClassification {
  const UrlClassification({
    required this.platform,
    required this.kind,
    required this.supportedByYtDlp,
    this.userWarning,
  });

  final MediaPlatform platform;
  final UrlKind kind;

  /// False for Spotify (DRM) and for input that isn't a usable http(s) URL.
  final bool supportedByYtDlp;

  /// Platform-static caveat to show before download (e.g. Spotify DRM,
  /// endless-mix cap, generic-extractor disclaimer). Contextual warnings that
  /// depend on device state (Reddit + broken FFmpeg, Instagram private) are
  /// applied by callers that know that state, not here.
  final String? userWarning;

  bool get isValidUrl => platform != MediaPlatform.unknown;
}

/// Classify [rawInput] by hostname/path patterns only. Never spawns a process.
UrlClassification classifyUrl(String rawInput) {
  final trimmed = rawInput.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return const UrlClassification(
      platform: MediaPlatform.unknown,
      kind: UrlKind.ambiguous,
      supportedByYtDlp: false,
    );
  }

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final path = uri.path.toLowerCase();

  if (_hostIs(host, ['youtube.com', 'youtu.be', 'youtube-nocookie.com']) ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com') {
    return _youtube(uri, host, path);
  }
  if (_hostIs(host, ['reddit.com']) || host == 'v.redd.it') {
    return const UrlClassification(
      platform: MediaPlatform.reddit,
      kind: UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  if (_hostIs(host, ['facebook.com']) ||
      host == 'fb.watch' ||
      host == 'fb.com' ||
      host == 'm.facebook.com') {
    return const UrlClassification(
      platform: MediaPlatform.facebook,
      kind: UrlKind.single,
      supportedByYtDlp: true,
      userWarning: AppStrings.warnPublicOnly,
    );
  }
  if (_hostIs(host, ['instagram.com'])) {
    final kind = path.contains('/reel') || path.contains('/p/')
        ? UrlKind.single
        : UrlKind.profile;
    return UrlClassification(
      platform: MediaPlatform.instagram,
      kind: kind,
      supportedByYtDlp: true,
      userWarning: AppStrings.warnPublicOnly,
    );
  }
  if (_hostIs(host, ['twitter.com', 'x.com'])) {
    return const UrlClassification(
      platform: MediaPlatform.twitter,
      kind: UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  if (_hostIs(host, ['tiktok.com']) || host == 'vm.tiktok.com') {
    return const UrlClassification(
      platform: MediaPlatform.tiktok,
      kind: UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  if (_hostIs(host, ['soundcloud.com'])) {
    // /sets/ is a SoundCloud playlist.
    return UrlClassification(
      platform: MediaPlatform.soundcloud,
      kind: path.contains('/sets/') ? UrlKind.playlist : UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  if (_hostIs(host, ['vimeo.com'])) {
    return const UrlClassification(
      platform: MediaPlatform.vimeo,
      kind: UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  if (_hostIs(host, ['twitch.tv']) || host == 'clips.twitch.tv') {
    final isVod = path.contains('/videos/') || path.startsWith('/v/');
    return UrlClassification(
      platform: MediaPlatform.twitch,
      kind: UrlKind.single,
      supportedByYtDlp: true,
      userWarning: isVod ? AppStrings.warnTwitchVod : null,
    );
  }
  if (_hostIs(host, ['spotify.com']) || host == 'open.spotify.com') {
    // yt-dlp cannot download Spotify (DRM) — flag it, don't spawn.
    return const UrlClassification(
      platform: MediaPlatform.spotify,
      kind: UrlKind.single,
      supportedByYtDlp: false,
      userWarning: AppStrings.errDrmSpotify,
    );
  }

  // Any other http(s) URL: let yt-dlp's generic extractor try.
  return const UrlClassification(
    platform: MediaPlatform.generic,
    kind: UrlKind.ambiguous,
    supportedByYtDlp: true,
    userWarning: AppStrings.warnGeneric,
  );
}

UrlClassification _youtube(Uri uri, String host, String path) {
  final list = uri.queryParameters['list'];
  final isMix = list != null && (list.startsWith('RD') || list.startsWith('UL'));
  if (isMix) {
    return const UrlClassification(
      platform: MediaPlatform.youtube,
      kind: UrlKind.playlist,
      supportedByYtDlp: true,
      userWarning: AppStrings.warnYoutubeMix,
    );
  }
  if (path.startsWith('/playlist') || (list != null && list.isNotEmpty)) {
    return const UrlClassification(
      platform: MediaPlatform.youtube,
      kind: UrlKind.playlist,
      supportedByYtDlp: true,
    );
  }
  // Channel URLs: /channel/, /c/, /user/, /@handle, or a /videos tab.
  if (path.startsWith('/channel/') ||
      path.startsWith('/c/') ||
      path.startsWith('/user/') ||
      path.startsWith('/@') ||
      path.endsWith('/videos')) {
    return const UrlClassification(
      platform: MediaPlatform.youtube,
      kind: UrlKind.channel,
      supportedByYtDlp: true,
    );
  }
  // youtu.be/<id>, /watch?v=, /shorts/<id>, /live/<id>
  if (host == 'youtu.be' ||
      path.startsWith('/watch') ||
      path.startsWith('/shorts/') ||
      path.startsWith('/live/') ||
      path.startsWith('/embed/')) {
    return const UrlClassification(
      platform: MediaPlatform.youtube,
      kind: UrlKind.single,
      supportedByYtDlp: true,
    );
  }
  return const UrlClassification(
    platform: MediaPlatform.youtube,
    kind: UrlKind.ambiguous,
    supportedByYtDlp: true,
  );
}

/// True if [host] equals a base domain or is a subdomain of it.
bool _hostIs(String host, List<String> domains) {
  for (final d in domains) {
    if (host == d || host.endsWith('.$d')) {
      return true;
    }
  }
  return false;
}
