import '../models/download_errors.dart';

/// Pre-flight free-space + duplicate decisions (Feature 3d).
///
/// The pure decision logic lives here so it's testable; the platform free-space
/// query (desktop FileStat, Android StatFs via the MethodChannel) is done at
/// the call site and its result passed in as [freeBytes].
class Preflight {
  const Preflight._();

  /// 500 MB floor used when the download size is unknown.
  static const int unknownSizeFloor = 500 * 1024 * 1024;

  /// Blocks with a [StorageFullError] when free space is insufficient.
  /// - Known estimate: require free ≥ 2× estimate (temp + final copy).
  /// - Unknown estimate: below the 500 MB floor only WARNS (never blocks).
  static PreflightResult checkStorage({
    int? estimatedBytes,
    required int freeBytes,
  }) {
    if (estimatedBytes != null && estimatedBytes > 0) {
      final required = estimatedBytes * 2;
      if (freeBytes < required) {
        return PreflightResult.blocked(
          StorageFullError(estimate: humanBytes(required - freeBytes)),
        );
      }
      return const PreflightResult.ok();
    }
    if (freeBytes < unknownSizeFloor) {
      return PreflightResult.warned(
        'Low storage (${humanBytes(freeBytes)} free). The download may fail.',
      );
    }
    return const PreflightResult.ok();
  }

  /// True when the same URL is already queued or downloading (Feature 3d).
  static bool isDuplicate(String url, Iterable<String> activeUrls) {
    final norm = url.trim();
    return activeUrls.any((u) => u.trim() == norm);
  }

  static String humanBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final str = value >= 10 || value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$str ${units[unit]}';
  }
}

class PreflightResult {
  const PreflightResult.ok() : blockingError = null, warning = null;
  const PreflightResult.blocked(AppError error)
    : blockingError = error,
      warning = null;
  const PreflightResult.warned(String message)
    : blockingError = null,
      warning = message;

  final AppError? blockingError;
  final String? warning;

  bool get isBlocked => blockingError != null;
}
