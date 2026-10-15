import '../app_strings.dart';

/// Suggested one-tap recovery for an [AppError] (Feature 3a).
///
/// Spec names retry/openSettings/checkNetwork/chooseFolder/updateEngine/none;
/// changePreset and checkAgain are added because FormatUnavailable and
/// LiveStream need distinct actions the UI branches on (deviation noted in
/// NOTES.md).
enum RecoveryAction {
  retry,
  openSettings,
  checkNetwork,
  chooseFolder,
  updateEngine,
  changePreset,
  checkAgain,
  none,
}

/// Every failure in the app is exactly one of these — no raw strings, no bare
/// `Exception`, no stack traces reaching the user (Feature 3).
sealed class AppError {
  const AppError({
    required this.userMessage,
    this.technicalDetail,
    this.isRetryable = false,
    this.suggestedAction = RecoveryAction.none,
  });

  /// Plain language, actionable, no jargon — the primary message.
  final String userMessage;

  /// For the expandable "Details" section and the diagnostics log only.
  final String? technicalDetail;

  final bool isRetryable;
  final RecoveryAction suggestedAction;

  String get kind => runtimeType.toString();

  @override
  String toString() =>
      '$kind(${technicalDetail ?? userMessage}, retryable=$isRetryable)';
}

final class InvalidUrlError extends AppError {
  const InvalidUrlError({super.technicalDetail})
    : super(userMessage: AppStrings.errInvalidUrl);
}

final class UnsupportedSiteError extends AppError {
  const UnsupportedSiteError({super.technicalDetail})
    : super(userMessage: AppStrings.errUnsupportedSite);
}

final class VideoUnavailableError extends AppError {
  const VideoUnavailableError({super.technicalDetail})
    : super(userMessage: AppStrings.errVideoUnavailable);
}

final class GeoBlockedError extends AppError {
  const GeoBlockedError({super.technicalDetail})
    : super(userMessage: AppStrings.errGeoBlocked);
}

final class AgeRestrictedError extends AppError {
  const AgeRestrictedError({super.technicalDetail})
    : super(userMessage: AppStrings.errAgeRestricted);
}

final class AuthRequiredError extends AppError {
  const AuthRequiredError({super.userMessage = AppStrings.errAuthRequired, super.technicalDetail});
}

final class NetworkError extends AppError {
  const NetworkError({super.technicalDetail})
    : super(
        userMessage: AppStrings.errNetwork,
        isRetryable: true,
        suggestedAction: RecoveryAction.checkNetwork,
      );
}

final class LiveStreamError extends AppError {
  const LiveStreamError({super.technicalDetail})
    : super(
        userMessage: AppStrings.errLiveStream,
        suggestedAction: RecoveryAction.checkAgain,
      );
}

final class DrmError extends AppError {
  const DrmError({super.userMessage = AppStrings.errDrmSpotify, super.technicalDetail});
}

final class FormatUnavailableError extends AppError {
  const FormatUnavailableError({super.technicalDetail})
    : super(
        userMessage: AppStrings.errFormatUnavailable,
        suggestedAction: RecoveryAction.changePreset,
      );
}

final class FfmpegError extends AppError {
  const FfmpegError({super.userMessage = AppStrings.errFfmpeg, super.technicalDetail})
    : super(isRetryable: true);
}

final class StorageFullError extends AppError {
  StorageFullError({String? estimate, super.technicalDetail})
    : super(
        userMessage: AppStrings.errStorageFull(estimate ?? 'some space'),
        isRetryable: true,
      );
}

final class PermissionError extends AppError {
  const PermissionError({super.technicalDetail})
    : super(
        userMessage: AppStrings.errPermission,
        suggestedAction: RecoveryAction.chooseFolder,
      );
}

final class EngineError extends AppError {
  const EngineError({super.userMessage = AppStrings.errEngine, super.technicalDetail})
    : super(isRetryable: true, suggestedAction: RecoveryAction.updateEngine);
}

/// User-initiated cancel — never surfaced as an error dialog.
final class CancelledError extends AppError {
  const CancelledError() : super(userMessage: 'Cancelled');
}

/// Platform switched off by remote config (Feature 5f). No technical detail is
/// exposed — don't advertise that this is a remote kill-switch.
final class PlatformDisabledError extends AppError {
  const PlatformDisabledError({required super.userMessage})
    : super(isRetryable: false);
}

final class UnknownError extends AppError {
  const UnknownError({super.technicalDetail})
    : super(
        userMessage: AppStrings.errUnknown,
        isRetryable: true,
      );
}
