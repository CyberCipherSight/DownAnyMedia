import '../services/url_classifier.dart';

/// GitHub-hosted remote config schema mirror (Feature 5).
///
/// Platforms not present in a fetched config default to ENABLED (fail-open):
/// a malformed or partial config must never silently disable a platform.

/// Google's public AdMob test unit IDs — safe to ship, used as compiled-in
/// defaults and when [kUseTestAds] forces test mode.
class TestAdUnits {
  const TestAdUnits._();
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
}

class AdFormatConfig {
  const AdFormatConfig({
    required this.enabled,
    required this.unitId,
    this.showAfterEveryNDownloads,
    this.adFreeHours,
  });

  final bool enabled;
  final String unitId;
  final int? showAfterEveryNDownloads; // interstitial only
  final int? adFreeHours; // rewarded only

  factory AdFormatConfig.fromJson(Map<String, dynamic> j, String fallbackUnit) {
    return AdFormatConfig(
      enabled: j['enabled'] == true,
      unitId: (j['unitId'] as String?)?.trim().isNotEmpty == true
          ? j['unitId'] as String
          : fallbackUnit,
      showAfterEveryNDownloads: (j['showAfterEveryNDownloads'] as num?)?.toInt(),
      adFreeHours: (j['adFreeHours'] as num?)?.toInt(),
    );
  }
}

class AdsConfig {
  const AdsConfig({
    required this.masterEnabled,
    required this.banner,
    required this.interstitial,
    required this.rewarded,
  });

  final bool masterEnabled;
  final AdFormatConfig banner;
  final AdFormatConfig interstitial;
  final AdFormatConfig rewarded;

  /// Interstitial frequency after safety clamp: 0 means never; any positive
  /// value is clamped to 1..50 so a config typo can't fire an interstitial
  /// after every single download (AdMob invalid-traffic risk, Feature 5g).
  int get clampedInterstitialFrequency {
    final n = interstitial.showAfterEveryNDownloads ?? 0;
    if (n <= 0) return 0;
    return n.clamp(1, 50);
  }

  int get rewardedAdFreeHours => (rewarded.adFreeHours ?? 1).clamp(1, 24);

  factory AdsConfig.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String k) =>
        (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    return AdsConfig(
      masterEnabled: j['masterEnabled'] != false, // default true
      banner: AdFormatConfig.fromJson(sub('banner'), TestAdUnits.banner),
      interstitial:
          AdFormatConfig.fromJson(sub('interstitial'), TestAdUnits.interstitial),
      rewarded: AdFormatConfig.fromJson(sub('rewarded'), TestAdUnits.rewarded),
    );
  }

  static const defaults = AdsConfig(
    masterEnabled: true,
    banner: AdFormatConfig(enabled: true, unitId: TestAdUnits.banner),
    interstitial: AdFormatConfig(
      enabled: true,
      unitId: TestAdUnits.interstitial,
      showAfterEveryNDownloads: 3,
    ),
    rewarded: AdFormatConfig(
      enabled: true,
      unitId: TestAdUnits.rewarded,
      adFreeHours: 1,
    ),
  );
}

class RemoteConfig {
  const RemoteConfig({
    required this.configVersion,
    required this.platforms,
    required this.ads,
    this.updatedAt,
    this.platformMessages = const {},
    this.notice,
  });

  final int configVersion;
  final DateTime? updatedAt;
  final Map<MediaPlatform, bool> platforms;
  final Map<MediaPlatform, String> platformMessages;
  final AdsConfig ads;
  final String? notice;

  /// Missing key ⇒ enabled (fail-open).
  bool isPlatformEnabled(MediaPlatform p) => platforms[p] ?? true;

  String? messageFor(MediaPlatform p) => platformMessages[p];

  /// Compiled-in default used when nothing else is available (Feature 5e):
  /// all platforms enabled, test ad IDs, interstitial N=3.
  static const defaults = RemoteConfig(
    configVersion: 0,
    platforms: {},
    ads: AdsConfig.defaults,
  );

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    final platforms = <MediaPlatform, bool>{};
    final rawPlatforms = (j['platforms'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final entry in rawPlatforms.entries) {
      final p = _platformByName(entry.key);
      if (p != null) platforms[p] = entry.value == true;
    }
    final messages = <MediaPlatform, String>{};
    final rawMessages =
        (j['platformMessages'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final entry in rawMessages.entries) {
      final p = _platformByName(entry.key);
      final v = entry.value;
      if (p != null && v is String && v.isNotEmpty) messages[p] = v;
    }
    return RemoteConfig(
      configVersion: (j['configVersion'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? ''),
      platforms: platforms,
      platformMessages: messages,
      ads: AdsConfig.fromJson(
        (j['ads'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      notice: (j['notice'] as String?)?.trim().isEmpty == true
          ? null
          : j['notice'] as String?,
    );
  }

  static MediaPlatform? _platformByName(String name) {
    for (final p in MediaPlatform.values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Pure interstitial-due decision (Feature 5g), unit-testable without the ad
/// SDK. Fires when [completedCount] lands on a multiple of [frequency].
bool interstitialDue(int completedCount, int frequency) =>
    frequency > 0 && completedCount > 0 && completedCount % frequency == 0;
