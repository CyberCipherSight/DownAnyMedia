import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:down_any_media/models/remote_config.dart';
import 'package:down_any_media/services/remote_config_crypto.dart';
import 'package:down_any_media/services/remote_config_service.dart';
import 'package:down_any_media/services/url_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _key = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));

Map<String, dynamic> _sampleConfig({int version = 1, bool spotify = false}) => {
  'configVersion': version,
  'platforms': {
    'youtube': true,
    'reddit': true,
    'facebook': true,
    'instagram': true,
    'twitter': true,
    'tiktok': true,
    'soundcloud': true,
    'vimeo': true,
    'twitch': true,
    'spotify': spotify,
    'generic': true,
  },
  'ads': {
    'masterEnabled': true,
    'interstitial': {'enabled': true, 'showAfterEveryNDownloads': 3},
  },
};

String _blob(Map<String, dynamic> cfg) =>
    RemoteConfigCrypto.encrypt(jsonEncode(cfg), _key);

RemoteConfigService _serviceReturning(String body, {int status = 200}) =>
    RemoteConfigService(
      client: MockClient((_) async => http.Response(body, status)),
      key: _key,
      configUrl: 'https://example.com/config',
    );

RemoteConfigService _serviceFailing() => RemoteConfigService(
  client: MockClient((_) async => throw const SocketException('offline')),
  key: _key,
  configUrl: 'https://example.com/config',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('crypto', () {
    test('round-trips plaintext', () {
      const plain = '{"hello":"world","n":3}';
      final blob = RemoteConfigCrypto.encrypt(plain, _key);
      expect(RemoteConfigCrypto.decrypt(blob, _key), plain);
    });

    test('rejects a tampered blob (GCM auth fails)', () {
      final blob = RemoteConfigCrypto.encrypt('{"a":1}', _key);
      final bytes = base64.decode(blob);
      bytes[bytes.length - 1] ^= 0xFF; // flip a tag byte
      final tampered = base64.encode(bytes);
      expect(
        () => RemoteConfigCrypto.decrypt(tampered, _key),
        throwsA(anything),
      );
    });

    test('rejects the wrong key', () {
      final blob = RemoteConfigCrypto.encrypt('{"a":1}', _key);
      final wrong = Uint8List.fromList(List.filled(32, 9));
      expect(() => RemoteConfigCrypto.decrypt(blob, wrong), throwsA(anything));
    });

    test('combineKeyParts XORs to the key', () {
      final a = List<int>.filled(32, 0xAA);
      final b = List<int>.filled(32, 0x0F);
      final combined = RemoteConfigCrypto.combineKeyParts([a, b]);
      expect(combined.every((x) => x == (0xAA ^ 0x0F)), isTrue);
    });
  });

  group('RemoteConfig model', () {
    test('spotify:false disables it; missing key defaults enabled', () {
      final cfg = RemoteConfig.fromJson(_sampleConfig(spotify: false));
      expect(cfg.isPlatformEnabled(MediaPlatform.spotify), isFalse);
      expect(cfg.isPlatformEnabled(MediaPlatform.youtube), isTrue);

      final partial = RemoteConfig.fromJson({
        'configVersion': 1,
        'platforms': {'youtube': false},
        'ads': const {},
      });
      expect(partial.isPlatformEnabled(MediaPlatform.youtube), isFalse);
      expect(
        partial.isPlatformEnabled(MediaPlatform.tiktok),
        isTrue,
      ); // missing
    });

    test('interstitial frequency is clamped (0=off, cap 50)', () {
      expect(
        AdsConfig.fromJson({
          'interstitial': {'showAfterEveryNDownloads': 999},
        }).clampedInterstitialFrequency,
        50,
      );
      expect(
        AdsConfig.fromJson({
          'interstitial': {'showAfterEveryNDownloads': 0},
        }).clampedInterstitialFrequency,
        0,
      );
      expect(
        AdsConfig.fromJson({
          'interstitial': {'showAfterEveryNDownloads': 3},
        }).clampedInterstitialFrequency,
        3,
      );
    });

    test('interstitialDue fires on multiples only', () {
      expect(interstitialDue(2, 2), isTrue);
      expect(interstitialDue(3, 2), isFalse);
      expect(interstitialDue(4, 2), isTrue);
      expect(interstitialDue(0, 2), isFalse);
      expect(interstitialDue(5, 0), isFalse); // off
    });

    test('unknown ad unit id falls back to test id', () {
      final ads = AdsConfig.fromJson({
        'banner': {'enabled': true, 'unitId': ''},
      });
      expect(ads.banner.unitId, TestAdUnits.banner);
    });
  });

  group('RemoteConfigService fallback chain', () {
    test('default build makes no remote config request', () async {
      var requests = 0;
      final svc = RemoteConfigService(
        client: MockClient((_) async {
          requests++;
          return http.Response('unexpected request', 500);
        }),
        configUrl: '',
      );
      addTearDown(svc.dispose);
      await svc.refresh();
      expect(requests, 0);
      expect(svc.config.configVersion, RemoteConfig.defaults.configVersion);
    });

    test('fresh fetch applies config', () async {
      final svc = _serviceReturning(_blob(_sampleConfig(version: 2)));
      await svc.refresh();
      expect(svc.config.configVersion, 2);
    });

    test('malformed JSON keeps current config', () async {
      final badBlob = RemoteConfigCrypto.encrypt('not json at all', _key);
      final svc = _serviceReturning(badBlob);
      await svc.refresh();
      expect(svc.config.configVersion, RemoteConfig.defaults.configVersion);
    });

    test('stale version is rejected', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(_sampleConfig(version: 5)),
        'remote_config_fetched_at': DateTime.now().millisecondsSinceEpoch,
      });
      final svc = _serviceReturning(_blob(_sampleConfig(version: 3)));
      await svc.initialize();
      await svc.refresh();
      expect(svc.config.configVersion, 5); // kept cached, ignored older
    });

    test('fetch failure with a cache keeps the cached config', () async {
      SharedPreferences.setMockInitialValues({
        'remote_config_cache': jsonEncode(_sampleConfig(version: 4)),
        'remote_config_fetched_at': DateTime.now().millisecondsSinceEpoch,
      });
      final svc = _serviceFailing();
      await svc.initialize();
      await svc.refresh();
      expect(svc.config.configVersion, 4);
    });

    test(
      'fetch failure with no cache falls back to compiled defaults',
      () async {
        final svc = _serviceFailing();
        await svc.initialize();
        await svc.refresh();
        expect(svc.config.configVersion, RemoteConfig.defaults.configVersion);
        expect(svc.config.isPlatformEnabled(MediaPlatform.youtube), isTrue);
      },
    );

    test('HTTP 404 (file deleted) stays fail-open on defaults', () async {
      final svc = _serviceReturning('not found', status: 404);
      await svc.refresh();
      expect(svc.config.isPlatformEnabled(MediaPlatform.tiktok), isTrue);
    });

    test('applied config gates a disabled platform', () async {
      final svc = _serviceReturning(
        _blob(_sampleConfig(version: 2, spotify: false)),
      );
      await svc.refresh();
      expect(svc.config.isPlatformEnabled(MediaPlatform.spotify), isFalse);
    });
  });
}
