import 'package:down_any_media/services/url_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyUrl', () {
    final cases = <String, (MediaPlatform, UrlKind, bool)>{
      // YouTube
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ':
          (MediaPlatform.youtube, UrlKind.single, true),
      'https://youtu.be/dQw4w9WgXcQ':
          (MediaPlatform.youtube, UrlKind.single, true),
      'https://www.youtube.com/shorts/abc123':
          (MediaPlatform.youtube, UrlKind.single, true),
      'https://www.youtube.com/playlist?list=PL123':
          (MediaPlatform.youtube, UrlKind.playlist, true),
      'https://www.youtube.com/watch?v=abc&list=PL123':
          (MediaPlatform.youtube, UrlKind.playlist, true),
      'https://www.youtube.com/watch?v=abc&list=RDabc':
          (MediaPlatform.youtube, UrlKind.playlist, true), // mix
      'https://www.youtube.com/@SomeCreator':
          (MediaPlatform.youtube, UrlKind.channel, true),
      'https://www.youtube.com/channel/UC123/videos':
          (MediaPlatform.youtube, UrlKind.channel, true),
      'https://music.youtube.com/watch?v=abc':
          (MediaPlatform.youtube, UrlKind.single, true),
      // Reddit
      'https://www.reddit.com/r/videos/comments/x/y/':
          (MediaPlatform.reddit, UrlKind.single, true),
      'https://v.redd.it/abcdef': (MediaPlatform.reddit, UrlKind.single, true),
      // Facebook
      'https://www.facebook.com/watch?v=123':
          (MediaPlatform.facebook, UrlKind.single, true),
      'https://fb.watch/abc/': (MediaPlatform.facebook, UrlKind.single, true),
      // Instagram
      'https://www.instagram.com/reel/abc/':
          (MediaPlatform.instagram, UrlKind.single, true),
      'https://www.instagram.com/p/abc/':
          (MediaPlatform.instagram, UrlKind.single, true),
      'https://www.instagram.com/someuser/':
          (MediaPlatform.instagram, UrlKind.profile, true),
      // Twitter/X
      'https://twitter.com/u/status/1':
          (MediaPlatform.twitter, UrlKind.single, true),
      'https://x.com/u/status/1': (MediaPlatform.twitter, UrlKind.single, true),
      // TikTok
      'https://www.tiktok.com/@u/video/1':
          (MediaPlatform.tiktok, UrlKind.single, true),
      'https://vm.tiktok.com/ABC/': (MediaPlatform.tiktok, UrlKind.single, true),
      // SoundCloud
      'https://soundcloud.com/artist/track':
          (MediaPlatform.soundcloud, UrlKind.single, true),
      'https://soundcloud.com/artist/sets/album':
          (MediaPlatform.soundcloud, UrlKind.playlist, true),
      // Vimeo
      'https://vimeo.com/123456789': (MediaPlatform.vimeo, UrlKind.single, true),
      // Twitch
      'https://www.twitch.tv/videos/123':
          (MediaPlatform.twitch, UrlKind.single, true),
      'https://www.twitch.tv/somestreamer':
          (MediaPlatform.twitch, UrlKind.single, true),
      // Spotify — not supported (DRM)
      'https://open.spotify.com/track/abc':
          (MediaPlatform.spotify, UrlKind.single, false),
      'https://spotify.com/track/abc':
          (MediaPlatform.spotify, UrlKind.single, false),
      // Generic
      'https://example.com/video.mp4':
          (MediaPlatform.generic, UrlKind.ambiguous, true),
      // Invalid
      'htp:/notaurl': (MediaPlatform.unknown, UrlKind.ambiguous, false),
      'just some text': (MediaPlatform.unknown, UrlKind.ambiguous, false),
      'ftp://example.com/x': (MediaPlatform.unknown, UrlKind.ambiguous, false),
      '': (MediaPlatform.unknown, UrlKind.ambiguous, false),
    };

    cases.forEach((url, expected) {
      test('"$url"', () {
        final result = classifyUrl(url);
        expect(result.platform, expected.$1, reason: 'platform for $url');
        expect(result.kind, expected.$2, reason: 'kind for $url');
        expect(result.supportedByYtDlp, expected.$3, reason: 'support for $url');
      });
    });

    test('spotify carries DRM warning', () {
      expect(classifyUrl('https://open.spotify.com/track/x').userWarning,
          contains('DRM'));
    });

    test('youtube mix carries endless-mix warning', () {
      expect(
          classifyUrl('https://www.youtube.com/watch?v=a&list=RDb').userWarning,
          contains('mix'));
    });

    test('invalid url is not marked valid', () {
      expect(classifyUrl('htp:/x').isValidUrl, isFalse);
      expect(classifyUrl('https://youtu.be/x').isValidUrl, isTrue);
    });
  });
}
