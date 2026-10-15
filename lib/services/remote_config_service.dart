import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_config.dart';
import 'app_log.dart';
import 'remote_config_crypto.dart';

/// Fetches, decrypts, and applies the GitHub-hosted config (Feature 5e).
///
/// FAIL-OPEN by design: fresh fetch → last-good cached config → compiled-in
/// defaults. Every failure (network, decrypt, malformed JSON, stale version)
/// lands silently in the fallback chain and is logged to [AppLog] — a
/// remote-config outage must never brick downloads.
class RemoteConfigService extends ChangeNotifier {
  RemoteConfigService({http.Client? client, Uint8List? key, String? configUrl})
    : _client = client ?? http.Client(),
      _key = key ?? _assembleKey(),
      _rawUrl = configUrl ?? const String.fromEnvironment('REMOTE_CONFIG_URL');

  // No account-specific endpoint or network request in the default build.
  final String _rawUrl;
  static const _cacheKey = 'remote_config_cache';
  static const _fetchedAtKey = 'remote_config_fetched_at';
  static const _fetchTimeout = Duration(seconds: 5);
  static const _refreshInterval = Duration(minutes: 15);

  final http.Client _client;
  final Uint8List _key;

  RemoteConfig _config = RemoteConfig.defaults;
  DateTime? _fetchedAt;

  RemoteConfig get config => _config;

  /// Load the cached config synchronously-ish from prefs, then kick off a
  /// fire-and-forget refresh. Safe to call once on app launch.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    final fetchedMillis = prefs.getInt(_fetchedAtKey);
    if (cached != null) {
      final parsed = _decodeJson(cached);
      if (parsed != null) {
        _config = parsed;
        _fetchedAt = fetchedMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(fetchedMillis);
        notifyListeners();
      }
    }
    // Fire-and-forget — never awaited by callers on a hot path.
    unawaited(refresh());
  }

  /// Refresh only if the cached config is older than 15 minutes (Feature 5e).
  Future<void> refreshIfStale() async {
    final at = _fetchedAt;
    if (at == null || DateTime.now().difference(at) >= _refreshInterval) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    final result = await _fetchAndDecode();
    if (result == null) {
      return; // keep current (cached or defaults); already logged.
    }
    final (fetched, rawJson) = result;
    // Guard against the CDN serving a stale blob after a push.
    if (fetched.configVersion < _config.configVersion) {
      AppLog.instance.info(
        'Remote config: ignored v${fetched.configVersion} < cached v${_config.configVersion}.',
      );
      return;
    }
    _config = fetched;
    _fetchedAt = DateTime.now();
    await _persist(rawJson);
    notifyListeners();
    AppLog.instance.info('Remote config applied: v${fetched.configVersion}.');
  }

  Future<(RemoteConfig, String)?> _fetchAndDecode() async {
    if (_rawUrl.isEmpty) return null;
    try {
      final url = Uri.parse(
        '$_rawUrl?v=${DateTime.now().millisecondsSinceEpoch}',
      );
      final resp = await _client.get(url).timeout(_fetchTimeout);
      if (resp.statusCode != 200) {
        AppLog.instance.warning('Remote config HTTP ${resp.statusCode}.');
        return null;
      }
      final json = RemoteConfigCrypto.decrypt(resp.body, _key);
      final config = _decodeJson(json);
      if (config == null) return null;
      return (config, json);
    } on Object catch (e) {
      // Decrypt/auth failure, timeout, socket error, malformed base64 — all
      // silent, fail-open.
      AppLog.instance.warning('Remote config fetch failed: $e');
      return null;
    }
  }

  RemoteConfig? _decodeJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;
      return RemoteConfig.fromJson(decoded.cast<String, dynamic>());
    } on Object catch (e) {
      AppLog.instance.warning('Remote config JSON invalid: $e');
      return null;
    }
  }

  Future<void> _persist(String rawJson) async {
    // Cache the decrypted JSON we last accepted so a cold start restores it.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, rawJson);
    await prefs.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  /// Placeholder key parts — the developer regenerates these from `secret.key`
  /// (see tools/remote_config/README.md). Until then the app simply fails to
  /// decrypt and stays on cached/default config (fail-open), which is correct.
  static Uint8List _assembleKey() {
    // Two zero-XOR placeholder parts. Replace both with the real
    // split of secret.key before shipping — the encrypt script prints them.
    final partA = List<int>.filled(32, 0);
    final partB = List<int>.filled(32, 0);
    return RemoteConfigCrypto.combineKeyParts([partA, partB]);
  }
}
