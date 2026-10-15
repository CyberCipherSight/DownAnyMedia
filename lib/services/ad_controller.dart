import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_config.dart';
import 'app_log.dart';

/// Compile-time escape hatch: forces Google test IDs regardless of config, for
/// development builds. Enable with `--dart-define=USE_TEST_ADS=true`.
const bool kUseTestAds =
    bool.fromEnvironment('USE_TEST_ADS', defaultValue: false);

/// Owns config-driven ad wiring (Feature 5g): effective unit IDs / flags, the
/// interstitial cadence (new format), and the persisted completed-download
/// counter. Banner and rewarded placement stay in the existing UI code; this
/// only supplies the resolved settings and drives the interstitial.
class AdController extends ChangeNotifier {
  AdController();

  static const _counterKey = 'downloads_since_interstitial';

  RemoteConfig _config = RemoteConfig.defaults;
  int _completedSinceInterstitial = 0;
  bool _interstitialPending = false;
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  bool get adsSupported => Platform.isAndroid;
  bool get masterEnabled => _config.ads.masterEnabled;

  bool get bannerEnabled =>
      adsSupported && masterEnabled && _config.ads.banner.enabled;
  String get bannerUnitId =>
      kUseTestAds ? TestAdUnits.banner : _config.ads.banner.unitId;

  bool get interstitialEnabled =>
      adsSupported && masterEnabled && _config.ads.interstitial.enabled;
  String get interstitialUnitId => kUseTestAds
      ? TestAdUnits.interstitial
      : _config.ads.interstitial.unitId;
  int get interstitialFrequency => _config.ads.clampedInterstitialFrequency;

  String get rewardedUnitId =>
      kUseTestAds ? TestAdUnits.rewarded : _config.ads.rewarded.unitId;
  int get rewardedAdFreeHours => _config.ads.rewardedAdFreeHours;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _completedSinceInterstitial = prefs.getInt(_counterKey) ?? 0;
    if (interstitialEnabled) {
      _preloadInterstitial();
    }
  }

  void updateConfig(RemoteConfig config) {
    _config = config;
    if (interstitialEnabled && _interstitial == null) {
      _preloadInterstitial();
    }
    notifyListeners();
  }

  /// Count a completed download (each playlist item counts). Flags an
  /// interstitial as pending when the count lands on a frequency multiple.
  /// Never shows here — showing waits for an idle moment.
  Future<void> registerCompletedDownload() async {
    if (!interstitialEnabled || interstitialFrequency == 0) {
      return;
    }
    _completedSinceInterstitial += 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_counterKey, _completedSinceInterstitial);
    if (interstitialDue(_completedSinceInterstitial, interstitialFrequency)) {
      _interstitialPending = true;
    }
  }

  /// Show a pending interstitial only when the app is idle (no active
  /// download/queue) and the ad-free window is not active. No-op otherwise.
  Future<void> maybeShowInterstitial({
    required bool isIdle,
    required bool adsHidden,
  }) async {
    if (!_interstitialPending ||
        !isIdle ||
        adsHidden ||
        !interstitialEnabled) {
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial(); // will show next idle moment once loaded
      return;
    }
    _interstitialPending = false;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        AppLog.instance.warning('Interstitial show failed: ${error.message}');
        _preloadInterstitial();
      },
    );
    await ad.show();
  }

  void _preloadInterstitial() {
    if (!interstitialEnabled || _interstitial != null || _loadingInterstitial) {
      return;
    }
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          // Skip silently, retry later — never block UX on an ad.
          AppLog.instance.warning('Interstitial load failed: ${error.message}');
        },
      ),
    );
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    super.dispose();
  }
}
