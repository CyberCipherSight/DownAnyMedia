import 'dart:io';

import 'package:down_any_media/models/download_errors.dart';
import 'package:down_any_media/services/error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

AppError map(String stderr) =>
    ErrorMapper.mapYtDlpFailure(exitCode: 1, stderr: stderr, stdout: '');

void main() {
  group('mapYtDlpFailure — real-ish yt-dlp stderr fixtures', () {
    final cases = <String, Type>{
      'ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users.':
          AgeRestrictedError,
      'ERROR: [youtube] abc: This live event will begin in 3 hours.':
          LiveStreamError,
      'ERROR: [youtube] abc: Premieres in 2 days': LiveStreamError,
      'ERROR: [youtube] abc: Video unavailable. This video is not available in your country':
          GeoBlockedError,
      'ERROR: [youtube] abc: Video unavailable': VideoUnavailableError,
      'ERROR: [youtube] abc: This video has been removed by the uploader':
          VideoUnavailableError,
      'ERROR: [youtube] abc: Private video. Sign in if you\'ve been granted access':
          VideoUnavailableError,
      'ERROR: [instagram] abc: Requested content is not available, rate-limit reached or login required':
          AuthRequiredError,
      'ERROR: [instagram] abc: This account is private': AuthRequiredError,
      'ERROR: This video is DRM protected': DrmError,
      'ERROR: [youtube] abc: Requested format is not available. Use --list-formats':
          FormatUnavailableError,
      'ERROR: Postprocessing: Error opening output files. ffmpeg exited with code 1':
          FfmpegError,
      'ERROR: unable to open file for writing: No space left on device':
          StorageFullError,
      'ERROR: unable to open for writing: Permission denied': PermissionError,
      'ERROR: [youtube] abc: Unable to extract player response; please report this issue':
          EngineError,
      'ERROR: nsig extraction failed: Some formats may be missing': EngineError,
      'ERROR: Unsupported URL: https://example.com/page': UnsupportedSiteError,
      'ERROR: No suitable extractor found for this url': UnsupportedSiteError,
      'ERROR: Unable to download webpage: <urlopen error [Errno -3] Temporary failure in name resolution>':
          NetworkError,
      'ERROR: Unable to download webpage: The read operation timed out':
          NetworkError,
      'ERROR: [generic] something completely unrecognized happened xyzzy':
          UnknownError,
    };

    cases.forEach((stderr, expectedType) {
      test('${expectedType.toString()} <- "${stderr.substring(0, stderr.length.clamp(0, 50))}…"',
          () {
        expect(map(stderr).runtimeType, expectedType);
      });
    });
  });

  test('retryable flags are correct', () {
    expect(map('connection reset by peer').isRetryable, isTrue); // network
    expect(map('Video unavailable').isRetryable, isFalse);
    expect(map('ffmpeg exited with code 1').isRetryable, isTrue);
  });

  test('technicalDetail is preserved for logs', () {
    const raw = 'ERROR: Video unavailable [detail xyz]';
    expect(map(raw).technicalDetail, contains('xyz'));
  });

  test('mapException maps SocketException to NetworkError', () {
    final err = ErrorMapper.mapException(
      const SocketException('Failed host lookup'),
    );
    expect(err, isA<NetworkError>());
  });

  test('age restriction wins over auth when both phrases present', () {
    expect(
      map('Sign in to confirm your age; login required').runtimeType,
      AgeRestrictedError,
    );
  });
}
