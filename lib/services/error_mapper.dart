import 'dart:io';

import '../models/download_errors.dart';

/// The single place yt-dlp / engine failures become typed [AppError]s
/// (Feature 3b). Used by BOTH engines: desktop passes real Process stderr;
/// Android forwards the youtubedl-android exception text over the MethodChannel
/// as `errorDetail` and maps it here — so the table lives in exactly one place.
///
/// Matching is case-insensitive, ordered specific → generic, first match wins.
class ErrorMapper {
  const ErrorMapper._();

  static final List<_Rule> _rules = [
    // Age restriction must precede auth (both mention "sign in").
    _Rule(
      RegExp(r'confirm your age|age.restricted|age restricted', caseSensitive: false),
      (d) => AgeRestrictedError(technicalDetail: d),
    ),
    // Live / upcoming.
    _Rule(
      RegExp(r'\bis live\b|premieres in|live event will begin|this live stream recording is not available',
          caseSensitive: false),
      (d) => LiveStreamError(technicalDetail: d),
    ),
    // Geo restriction.
    _Rule(
      RegExp(r'not available in your country|geo.?restricted|blocked it in your country|not available from your location',
          caseSensitive: false),
      (d) => GeoBlockedError(technicalDetail: d),
    ),
    // Video gone / private / deleted (before auth, which catches "private account").
    _Rule(
      RegExp(r'video unavailable|has been removed|private video|this video is (private|unavailable)|no longer available|been terminated|does not exist|\bdeleted\b',
          caseSensitive: false),
      (d) => VideoUnavailableError(technicalDetail: d),
    ),
    // DRM.
    _Rule(
      RegExp(r'drm protected|is drm|protected by drm', caseSensitive: false),
      (d) => DrmError(technicalDetail: d),
    ),
    // Auth / login walls / rate limit.
    _Rule(
      RegExp(r'login required|requires authentication|rate.?limit reached|use --cookies|requires login|sign in to|private account|this account is private|you need to log in',
          caseSensitive: false),
      (d) => AuthRequiredError(technicalDetail: d),
    ),
    // Format ladder exhausted.
    _Rule(
      RegExp(r'requested format is not available|no video formats found|no formats found|no suitable formats|only images are available',
          caseSensitive: false),
      (d) => FormatUnavailableError(technicalDetail: d),
    ),
    // FFmpeg / postprocessing / merge.
    _Rule(
      RegExp(r'\bffmpeg\b|postprocessing|merging formats|conversion failed|ffprobe',
          caseSensitive: false),
      (d) => FfmpegError(technicalDetail: d),
    ),
    // Storage.
    _Rule(
      RegExp(r'no space left|enospc|not enough space|disk quota exceeded',
          caseSensitive: false),
      (d) => StorageFullError(technicalDetail: d),
    ),
    // Filesystem permission.
    _Rule(
      RegExp(r'permission denied|unable to open .* for writing|read-only file system|\beacces\b',
          caseSensitive: false),
      (d) => PermissionError(technicalDetail: d),
    ),
    // Engine breakage — YouTube extractor/signature failures are almost always
    // a stale yt-dlp (Feature 4.5): suggest engine update.
    _Rule(
      RegExp(r'unable to extract|signature extraction failed|nsig extraction|unable to decode|player response|no module named|python',
          caseSensitive: false),
      (d) => EngineError(technicalDetail: d),
    ),
    // Unsupported site.
    _Rule(
      RegExp(r'unsupported url|no suitable extractor|is not a supported url|generic extractor.*failed',
          caseSensitive: false),
      (d) => UnsupportedSiteError(technicalDetail: d),
    ),
    // Network — kept late so specific failures win first.
    _Rule(
      RegExp(r'unable to download|connection refused|connection reset|connection aborted|timed out|\btimeout\b|getaddrinfo|\bssl\b|network is unreachable|temporary failure in name resolution|urlopen error|remote end closed|failed to resolve|failed host lookup|name or service not known',
          caseSensitive: false),
      (d) => NetworkError(technicalDetail: d),
    ),
  ];

  static AppError mapYtDlpFailure({
    required int exitCode,
    required String stderr,
    required String stdout,
  }) {
    final haystack = '$stderr\n$stdout';
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(haystack)) {
        return rule.build(_snippet(stderr, stdout));
      }
    }
    return UnknownError(technicalDetail: _snippet(stderr, stdout));
  }

  /// Map a thrown Dart exception (analysis/publish path) to an [AppError].
  static AppError mapException(Object error) {
    if (error is SocketException || error is HttpException) {
      return NetworkError(technicalDetail: error.toString());
    }
    if (error is FileSystemException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('space') || msg.contains('enospc')) {
        return StorageFullError(technicalDetail: error.toString());
      }
      if (msg.contains('permission') || msg.contains('denied')) {
        return PermissionError(technicalDetail: error.toString());
      }
    }
    // Fall back to the stderr table using the message text.
    return mapYtDlpFailure(exitCode: -1, stderr: error.toString(), stdout: '');
  }

  static String _snippet(String stderr, String stdout) {
    final text = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    return text.length > 2000 ? text.substring(text.length - 2000) : text;
  }
}

class _Rule {
  _Rule(this.pattern, this.build);
  final RegExp pattern;
  final AppError Function(String? detail) build;
}
