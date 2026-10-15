import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _androidDownloaderChannel = MethodChannel(
  'down_any_media/android_downloader',
);

const String _downloadFolderPreference = 'download_folder';
const String _historyPreference = 'download_history';
const String _queueStatePreference = 'download_queue_state';
const String _playlistFilenameStylePreference = 'playlist_filename_style';
const String _embedMetadataPreference = 'embed_metadata';
const String _embedThumbnailPreference = 'embed_thumbnail';
const String _audioQualityPreference = 'audio_quality';
const String _videoQualityPreference = 'video_quality';
const String _adsHiddenUntilPreference = 'ads_hidden_until';
const String _themeModePreference = 'theme_mode';
const String _smartUrlCleaningPreference = 'smart_url_cleaning';
const Duration _adRemovalDuration = Duration(hours: 1);

class AdMobTestIds {
  const AdMobTestIds._();

  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const rewardedInterstitial = 'ca-app-pub-3940256099942544/5354046379';
  static const appOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const native = 'ca-app-pub-3940256099942544/2247696110';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await MobileAds.instance.initialize();
  }
  runApp(const DownAnyMediaApp());
}

enum DownloadStage {
  waiting('Waiting'),
  analyzing('Analyzing'),
  updatingEngine('Preparing Download Engine'),
  downloading('Downloading'),
  extracting('Preparing audio'),
  converting('Media Processing'),
  publishing('Saving file'),
  completed('Completed'),
  failed('Failed'),
  cancelled('Cancelled');

  const DownloadStage(this.label);

  final String label;
}

enum UrlAnalysisStatus {
  idle,
  analyzing,
  single,
  playlist,
  unsupported,
  failed,
}

enum QueueItemStatus {
  waiting('Waiting'),
  analyzing('Analyzing'),
  downloading('Downloading'),
  converting('Converting'),
  publishing('Publishing'),
  completed('Completed'),
  failed('Failed'),
  skipped('Skipped'),
  cancelled('Cancelled');

  const QueueItemStatus(this.label);

  final String label;
}

enum PlaylistFilenameStyle {
  originalTitleOnly('Original title only'),
  numberedPlaylistOrder('Numbered playlist order');

  const PlaylistFilenameStyle(this.label);

  final String label;
}

enum AudioQualityPreset {
  best('Best', '0'),
  good('Good', '5'),
  smallerFile('Smaller file', '9');

  const AudioQualityPreset(this.label, this.ytDlpValue);

  final String label;
  final String ytDlpValue;
}

enum DownloadMode {
  mp3('Audio', 'Audio'),
  video('Video', 'Video');

  const DownloadMode(this.label, this.historyLabel);

  final String label;
  final String historyLabel;
}

enum AppThemeMode {
  system('System default', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  const AppThemeMode(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;
}

AppThemeMode _appThemeModeFromName(String? name) {
  return AppThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => AppThemeMode.system,
  );
}

enum VideoQualityPreset {
  best('Best', 'bv*+ba/best'),
  p1080('1080p', 'bv*[height<=1080]+ba/b[height<=1080]/best'),
  p720('720p', 'bv*[height<=720]+ba/b[height<=720]/best'),
  p480('480p', 'bv*[height<=480]+ba/b[height<=480]/best'),
  smallest('Smallest', 'worst');

  const VideoQualityPreset(this.label, this.formatSelector);

  final String label;
  final String formatSelector;

  bool get mayFallback => this != best && this != smallest;
}

VideoQualityPreset? _videoQualityFromName(String? name) {
  if (name == null) {
    return null;
  }
  for (final quality in VideoQualityPreset.values) {
    if (quality.name == name) {
      return quality;
    }
  }
  return null;
}

class PlaylistEntry {
  const PlaylistEntry({
    required this.title,
    required this.url,
    required this.index,
  });

  final String title;
  final String url;
  final int index;
}

class PlaylistInfo {
  const PlaylistInfo({
    required this.sourceUrl,
    required this.status,
    this.title,
    this.totalCount,
    this.items = const [],
    this.error,
  });

  final String sourceUrl;
  final UrlAnalysisStatus status;
  final String? title;
  final int? totalCount;
  final List<PlaylistEntry> items;
  final String? error;

  bool get isPlaylist => status == UrlAnalysisStatus.playlist;
  bool get isSingle => status == UrlAnalysisStatus.single;
}

class DownloadQueueItem {
  DownloadQueueItem({
    required this.title,
    required this.url,
    required this.index,
    this.status = QueueItemStatus.waiting,
    this.downloadMode = DownloadMode.mp3,
    this.videoQuality,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String title;
  final String url;
  final int index;
  final DateTime createdAt;
  final DownloadMode downloadMode;
  final VideoQualityPreset? videoQuality;
  QueueItemStatus status;
  double? progress;
  String? filePath;
  String? error;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'index': index,
    'status': status.name,
    'downloadMode': downloadMode.name,
    if (videoQuality != null) 'videoQuality': videoQuality!.name,
    'createdAt': createdAt.toIso8601String(),
    if (progress != null) 'progress': progress,
    if (filePath != null) 'filePath': filePath,
    if (error != null) 'error': error,
  };

  static DownloadQueueItem? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final title = value['title']?.toString();
    final url = value['url']?.toString();
    final index = int.tryParse(value['index']?.toString() ?? '');
    if (title == null || url == null || index == null) {
      return null;
    }
    final item = DownloadQueueItem(
      title: title,
      url: url,
      index: index,
      status: QueueItemStatus.values.firstWhere(
        (status) => status.name == value['status']?.toString(),
        orElse: () => QueueItemStatus.waiting,
      ),
      downloadMode: DownloadMode.values.firstWhere(
        (mode) => mode.name == value['downloadMode']?.toString(),
        orElse: () => DownloadMode.mp3,
      ),
      videoQuality: _videoQualityFromName(value['videoQuality']?.toString()),
      createdAt:
          DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
    item.progress = double.tryParse(value['progress']?.toString() ?? '');
    item.filePath = value['filePath']?.toString();
    item.error = value['error']?.toString();
    return item;
  }
}

class DownloadOutcome {
  const DownloadOutcome({
    required this.success,
    this.fileName,
    this.filePath,
    this.contentUri,
    this.warning,
    this.error,
    this.selectedFormat,
    this.fallbackStepsTried = const [],
    this.finalFilePath,
    this.tempFolder,
    this.publishResult,
    this.ffmpegAvailable,
    this.ffmpegPath,
    this.ffmpegVersion,
    this.ffmpegExecutionTest,
    this.androidAbi,
    this.videoMergeSupported,
    this.filesFound = const [],
    this.fallbackAttempted = false,
    this.cancelled = false,
  });

  final bool success;
  final String? fileName;
  final String? filePath;
  final String? contentUri;
  final String? warning;
  final String? error;
  final String? selectedFormat;
  final List<String> fallbackStepsTried;
  final String? finalFilePath;
  final String? tempFolder;
  final String? publishResult;
  final bool? ffmpegAvailable;
  final String? ffmpegPath;
  final String? ffmpegVersion;
  final String? ffmpegExecutionTest;
  final String? androidAbi;
  final bool? videoMergeSupported;
  final List<String> filesFound;
  final bool fallbackAttempted;
  final bool cancelled;
}

class UrlIntakeResult {
  const UrlIntakeResult({
    required this.originalUrl,
    required this.cleanedUrl,
    required this.workingUrl,
    required this.platform,
    required this.info,
    required this.cleanedAttempted,
    required this.usedOriginalFallback,
    this.cleanedError,
  });

  final String originalUrl;
  final String cleanedUrl;
  final String workingUrl;
  final String platform;
  final PlaylistInfo info;
  final bool cleanedAttempted;
  final bool usedOriginalFallback;
  final String? cleanedError;

  bool get cleanedChanged => cleanedUrl != originalUrl;
  bool get cleanedWorked => cleanedAttempted && workingUrl == cleanedUrl;
}

class SavedQueueState {
  const SavedQueueState({
    required this.title,
    required this.outputFolder,
    required this.createdAt,
    required this.items,
  });

  final String title;
  final String outputFolder;
  final DateTime createdAt;
  final List<DownloadQueueItem> items;
}

class CompletedDownload {
  const CompletedDownload({
    required this.fileName,
    required this.filePath,
    required this.platform,
    required this.completedAt,
    this.isPlaylist = false,
    this.totalCount,
    this.completedCount,
    this.failedCount,
    this.skippedCount,
    this.folderPathOverride,
    this.contentUri,
    this.downloadMode = DownloadMode.mp3,
    this.videoQualityLabel,
  });

  final String fileName;
  final String filePath;
  final String platform;
  final DateTime completedAt;
  final bool isPlaylist;
  final int? totalCount;
  final int? completedCount;
  final int? failedCount;
  final int? skippedCount;
  final String? folderPathOverride;
  final String? contentUri;
  final DownloadMode downloadMode;
  final String? videoQualityLabel;

  String get folderPath =>
      folderPathOverride ??
      (Platform.isAndroid
          ? '/storage/emulated/0/Download/DownAnyMedia'
          : File(filePath).parent.path);

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'filePath': filePath,
    'platform': platform,
    'completedAt': completedAt.toIso8601String(),
    'isPlaylist': isPlaylist,
    if (totalCount != null) 'totalCount': totalCount,
    if (completedCount != null) 'completedCount': completedCount,
    if (failedCount != null) 'failedCount': failedCount,
    if (skippedCount != null) 'skippedCount': skippedCount,
    if (folderPathOverride != null) 'folderPathOverride': folderPathOverride,
    if (contentUri != null) 'contentUri': contentUri,
    'downloadMode': downloadMode.name,
    if (videoQualityLabel != null) 'videoQualityLabel': videoQualityLabel,
  };

  static CompletedDownload? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final fileName = value['fileName']?.toString();
    final filePath = value['filePath']?.toString();
    final platform = value['platform']?.toString();
    final completedAt = DateTime.tryParse(
      value['completedAt']?.toString() ?? '',
    );
    if (fileName == null ||
        filePath == null ||
        platform == null ||
        completedAt == null) {
      return null;
    }
    return CompletedDownload(
      fileName: fileName,
      filePath: filePath,
      platform: platform,
      completedAt: completedAt,
      isPlaylist: value['isPlaylist'] == true,
      totalCount: int.tryParse(value['totalCount']?.toString() ?? ''),
      completedCount: int.tryParse(value['completedCount']?.toString() ?? ''),
      failedCount: int.tryParse(value['failedCount']?.toString() ?? ''),
      skippedCount: int.tryParse(value['skippedCount']?.toString() ?? ''),
      folderPathOverride: value['folderPathOverride']?.toString(),
      contentUri: value['contentUri']?.toString(),
      downloadMode: DownloadMode.values.firstWhere(
        (mode) => mode.name == value['downloadMode']?.toString(),
        orElse: () => DownloadMode.mp3,
      ),
      videoQualityLabel: value['videoQualityLabel']?.toString(),
    );
  }
}

class ToolPaths {
  const ToolPaths({
    required this.ytDlp,
    required this.ffmpeg,
    required this.ffmpegIsBundled,
    required this.ytDlpVersion,
    required this.ffmpegVersion,
  });

  final String ytDlp;
  final String ffmpeg;
  final bool ffmpegIsBundled;
  final String ytDlpVersion;
  final String ffmpegVersion;
}

class EngineInfo {
  const EngineInfo({
    required this.platformLabel,
    required this.status,
    required this.ytDlpAvailable,
    required this.ffmpegAvailable,
    required this.ytDlpVersion,
    required this.ffmpegVersion,
    required this.activeEnginePath,
    required this.androidUpdateStatus,
    this.ffmpegPath,
    this.ffmpegExecutionTest,
    this.androidAbi,
    this.videoMergeSupported,
    this.message,
  });

  final String platformLabel;
  final String status;
  final bool ytDlpAvailable;
  final bool ffmpegAvailable;
  final String ytDlpVersion;
  final String ffmpegVersion;
  final String activeEnginePath;
  final String androidUpdateStatus;
  final String? ffmpegPath;
  final String? ffmpegExecutionTest;
  final String? androidAbi;
  final bool? videoMergeSupported;
  final String? message;

  factory EngineInfo.initial() => EngineInfo(
    platformLabel: _platformLabel(),
    status: 'Checking',
    ytDlpAvailable: false,
    ffmpegAvailable: false,
    ytDlpVersion: 'Unknown',
    ffmpegVersion: 'Unknown',
    activeEnginePath: 'Checking...',
    androidUpdateStatus: Platform.isAndroid ? 'Not checked' : 'N/A',
    ffmpegPath: null,
    ffmpegExecutionTest: null,
    androidAbi: null,
    videoMergeSupported: null,
  );

  factory EngineInfo.fromAndroid(Map<dynamic, dynamic>? value) => EngineInfo(
    platformLabel: 'Android',
    status: value?['status']?.toString() ?? 'Engine error',
    ytDlpAvailable: value?['ytDlpAvailable'] == true,
    ffmpegAvailable: value?['ffmpegAvailable'] == true,
    ytDlpVersion: value?['ytDlpVersion']?.toString() ?? 'Unknown',
    ffmpegVersion: value?['ffmpegVersion']?.toString() ?? 'Unknown',
    activeEnginePath:
        value?['activeEnginePath']?.toString() ?? 'Bundled Android engine',
    androidUpdateStatus:
        value?['androidUpdateStatus']?.toString() ?? 'Not checked',
    ffmpegPath: value?['ffmpegPath']?.toString(),
    ffmpegExecutionTest: value?['ffmpegExecutionTest']?.toString(),
    androidAbi: value?['androidAbi']?.toString(),
    videoMergeSupported: value?['videoMergeSupported'] == true,
    message: value?['message']?.toString(),
  );

  bool get canDownload => ytDlpAvailable && ffmpegAvailable;
}

class DownAnyMediaApp extends StatefulWidget {
  const DownAnyMediaApp({super.key});

  @override
  State<DownAnyMediaApp> createState() => _DownAnyMediaAppState();
}

class _DownAnyMediaAppState extends State<DownAnyMediaApp> {
  AppThemeMode _themeMode = AppThemeMode.system;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemeMode());
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = _appThemeModeFromName(prefs.getString(_themeModePreference));
    });
  }

  Future<void> _setThemeMode(AppThemeMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePreference, value.name);
    if (mounted) {
      setState(() => _themeMode = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00796B);

    return MaterialApp(
      title: 'DownAnyMedia',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: DownloaderPage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AppThemeMode themeMode;
  final Future<void> Function(AppThemeMode value) onThemeModeChanged;

  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  final TextEditingController _urlController = TextEditingController();
  final List<CompletedDownload> _completedDownloads = [];
  final List<String> _recentLogLines = [];
  final List<DownloadQueueItem> _queueItems = [];

  DownloadStage _stage = DownloadStage.waiting;
  EngineInfo _engineInfo = EngineInfo.initial();
  PlaylistInfo? _playlistInfo;
  Timer? _analysisTimer;
  Process? _downloadProcess;
  double? _progress;
  double? _totalProgress;
  String? _speed;
  String? _eta;
  String? _message;
  String? _incomingUrlMessage;
  String? _outputFolder;
  String? _queueTitle;
  String? _queueOutputFolder;
  DateTime? _queueCreatedAt;
  String? _lastAnalyzedUrl;
  int _activeQueueIndex = -1;
  bool _queuePaused = false;
  bool _queuePauseRequested = false;
  PlaylistFilenameStyle _playlistFilenameStyle =
      PlaylistFilenameStyle.originalTitleOnly;
  bool _embedMetadata = true;
  bool _embedThumbnail = true;
  bool _smartUrlCleaning = false;
  AudioQualityPreset _audioQualityPreset = AudioQualityPreset.best;
  DownloadMode _downloadMode = DownloadMode.mp3;
  VideoQualityPreset _videoQualityPreset = VideoQualityPreset.best;
  bool _cancelRequested = false;
  bool _queueCancelRequested = false;
  String? _androidProcessId;
  DateTime? _adsHiddenUntil;
  DateTime _lastProgressUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _adResumeTimer;
  BannerAd? _bannerAd;
  RewardedAd? _rewardedAd;
  bool _bannerAdLoaded = false;
  bool _rewardedAdLoading = false;

  bool get _isRunning => _downloadProcess != null || _androidProcessId != null;
  bool get _adsSupported => Platform.isAndroid;
  bool get _adsHidden =>
      _adsHiddenUntil != null && _adsHiddenUntil!.isAfter(DateTime.now());
  bool get _shouldShowAds => _adsSupported && !_adsHidden;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _androidDownloaderChannel.setMethodCallHandler(_handleAndroidMethodCall);
    }
    unawaited(_loadInitialState());
    unawaited(_loadAdState());
    if (Platform.isAndroid) {
      unawaited(_loadInitialSharedContent());
    }
  }

  @override
  void dispose() {
    if (!Platform.isAndroid) {
      _downloadProcess?.kill();
    }
    _urlController.dispose();
    _analysisTimer?.cancel();
    _adResumeTimer?.cancel();
    _bannerAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  Future<void> _loadAdState() async {
    if (!_adsSupported) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hiddenUntilMillis = prefs.getInt(_adsHiddenUntilPreference);
    final hiddenUntil = hiddenUntilMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(hiddenUntilMillis);

    if (!mounted) {
      return;
    }

    if (hiddenUntil != null && hiddenUntil.isAfter(DateTime.now())) {
      setState(() => _adsHiddenUntil = hiddenUntil);
      _disposeBannerAd();
      _scheduleAdResume();
      return;
    }

    if (hiddenUntilMillis != null) {
      await prefs.remove(_adsHiddenUntilPreference);
    }
    _loadBannerAd();
  }

  void _loadBannerAd() {
    if (!_shouldShowAds || _bannerAd != null) {
      return;
    }

    final bannerAd = BannerAd(
      adUnitId: AdMobTestIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || !_shouldShowAds || ad != _bannerAd) {
            ad.dispose();
            return;
          }
          setState(() => _bannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted || ad != _bannerAd) {
            return;
          }
          setState(() {
            _bannerAd = null;
            _bannerAdLoaded = false;
          });
          _rememberLog('Banner ad failed to load: ${error.message}');
        },
      ),
    );

    _bannerAd = bannerAd;
    unawaited(bannerAd.load());
  }

  void _disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _bannerAdLoaded = false;
  }

  Future<void> _showRewardedAdForAdRemoval() async {
    if (!_adsSupported || _adsHidden || _rewardedAdLoading) {
      return;
    }

    setState(() => _rewardedAdLoading = true);
    _showSnack('Loading reward video...');

    try {
      await RewardedAd.load(
        adUnitId: AdMobTestIds.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!mounted || _adsHidden) {
              ad.dispose();
              return;
            }

            var rewardEarned = false;
            _rewardedAd = ad;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                if (!mounted) {
                  return;
                }
                setState(() => _rewardedAd = null);
                if (!rewardEarned && !_adsHidden) {
                  _showSnack('Watch the full video to hide ads.');
                }
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                if (!mounted) {
                  return;
                }
                setState(() => _rewardedAd = null);
                _showSnack('Reward video could not be shown. Try again.');
                _rememberLog('Rewarded ad failed to show: ${error.message}');
              },
            );

            setState(() => _rewardedAdLoading = false);
            ad.show(
              onUserEarnedReward: (ad, reward) {
                rewardEarned = true;
                unawaited(_hideAdsForOneHour());
              },
            );
          },
          onAdFailedToLoad: (error) {
            if (!mounted) {
              return;
            }
            setState(() => _rewardedAdLoading = false);
            _showSnack('Reward video is unavailable. Try again later.');
            _rememberLog('Rewarded ad failed to load: ${error.message}');
          },
        ),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _rewardedAdLoading = false);
      _showSnack('Reward video is unavailable. Try again later.');
      _rememberLog('Rewarded ad error: $error');
    }
  }

  Future<void> _hideAdsForOneHour() async {
    final hiddenUntil = DateTime.now().add(_adRemovalDuration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _adsHiddenUntilPreference,
      hiddenUntil.millisecondsSinceEpoch,
    );

    if (!mounted) {
      return;
    }

    _disposeBannerAd();
    setState(() => _adsHiddenUntil = hiddenUntil);
    _scheduleAdResume();
    _showSnack('Ads hidden until ${_formatDateTime(hiddenUntil)}.');
  }

  void _scheduleAdResume() {
    _adResumeTimer?.cancel();
    final hiddenUntil = _adsHiddenUntil;
    if (hiddenUntil == null) {
      return;
    }

    final delay = hiddenUntil.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _restoreAdsAfterExpiry();
      return;
    }

    _adResumeTimer = Timer(delay + const Duration(seconds: 1), () {
      _restoreAdsAfterExpiry();
    });
  }

  void _restoreAdsAfterExpiry() {
    if (!mounted) {
      return;
    }

    if (_adsHidden) {
      _scheduleAdResume();
      return;
    }

    setState(() => _adsHiddenUntil = null);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.remove(_adsHiddenUntilPreference),
      ),
    );
    _loadBannerAd();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget? _buildBannerAdBar() {
    final bannerAd = _bannerAd;
    if (!_shouldShowAds || !_bannerAdLoaded || bannerAd == null) {
      return null;
    }

    return SafeArea(
      top: false,
      child: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: bannerAd.size.height.toDouble(),
          width: double.infinity,
          child: Center(
            child: SizedBox(
              width: bannerAd.size.width.toDouble(),
              height: bannerAd.size.height.toDouble(),
              child: AdWidget(ad: bannerAd),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedFolder = prefs.getString(_downloadFolderPreference);
    final folder = Platform.isAndroid
        ? storedFolder ?? await _resolveDefaultDownloadFolder()
        : storedFolder ?? await _resolveDefaultDownloadFolder();
    final history = prefs
        .getStringList(_historyPreference)
        ?.map((item) => CompletedDownload.fromJson(jsonDecode(item)))
        .whereType<CompletedDownload>()
        .toList();
    final queueState = _decodeQueueState(
      prefs.getString(_queueStatePreference),
    );
    final playlistStyle = PlaylistFilenameStyle.values.firstWhere(
      (style) =>
          style.name == prefs.getString(_playlistFilenameStylePreference),
      orElse: () => PlaylistFilenameStyle.originalTitleOnly,
    );
    final audioQuality = AudioQualityPreset.values.firstWhere(
      (preset) => preset.name == prefs.getString(_audioQualityPreference),
      orElse: () => AudioQualityPreset.best,
    );
    final videoQuality = VideoQualityPreset.values.firstWhere(
      (quality) => quality.name == prefs.getString(_videoQualityPreference),
      orElse: () => VideoQualityPreset.best,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _outputFolder = folder;
      _playlistFilenameStyle = playlistStyle;
      _embedMetadata = prefs.getBool(_embedMetadataPreference) ?? true;
      _embedThumbnail = prefs.getBool(_embedThumbnailPreference) ?? true;
      _smartUrlCleaning = prefs.getBool(_smartUrlCleaningPreference) ?? false;
      _audioQualityPreset = audioQuality;
      _downloadMode = DownloadMode.mp3;
      _videoQualityPreset = videoQuality;
      if (history != null) {
        _completedDownloads
          ..clear()
          ..addAll(history);
      }
      if (queueState != null) {
        _queueTitle = queueState.title;
        _queueOutputFolder = queueState.outputFolder;
        _queueCreatedAt = queueState.createdAt;
        _activeQueueIndex = -1;
        _queuePaused = queueState.items.any(
          (item) =>
              item.status == QueueItemStatus.waiting ||
              item.status == QueueItemStatus.failed ||
              item.status == QueueItemStatus.cancelled,
        );
        _queueItems
          ..clear()
          ..addAll(queueState.items.map(_normalizeRestoredQueueItem));
        _totalProgress = _queueItems.isEmpty ? null : _restoredQueueProgress();
        if (_queueItems.isNotEmpty) {
          _message =
              'Restored saved queue. Review it, then resume or retry when ready.';
        }
      }
    });
    await _refreshEngineStatus();
  }

  Future<void> _refreshEngineStatus() async {
    setState(() => _engineInfo = EngineInfo.initial());
    try {
      final info = Platform.isAndroid
          ? await _readAndroidEngineInfo()
          : await _readDesktopEngineInfo();
      if (mounted) {
        setState(() => _engineInfo = info);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _engineInfo = EngineInfo(
            platformLabel: _platformLabel(),
            status: 'Engine error',
            ytDlpAvailable: false,
            ffmpegAvailable: false,
            ytDlpVersion: 'Unknown',
            ffmpegVersion: 'Unknown',
            activeEnginePath: 'Unavailable',
            androidUpdateStatus: Platform.isAndroid ? 'Unknown' : 'N/A',
            ffmpegPath: null,
            ffmpegExecutionTest: null,
            androidAbi: null,
            videoMergeSupported: null,
            message: _friendlyException(error),
          );
        });
      }
    }
  }

  SavedQueueState? _decodeQueueState(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return null;
      }
      final itemsRaw = decoded['items'];
      final items = itemsRaw is List
          ? itemsRaw
                .map(DownloadQueueItem.fromJson)
                .whereType<DownloadQueueItem>()
                .toList()
          : <DownloadQueueItem>[];
      if (items.isEmpty) {
        return null;
      }
      return SavedQueueState(
        title: decoded['title']?.toString() ?? 'Saved queue',
        outputFolder:
            decoded['outputFolder']?.toString() ??
            (_outputFolder ?? _defaultDownloadsBase()),
        createdAt:
            DateTime.tryParse(decoded['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        items: items,
      );
    } on Object {
      return null;
    }
  }

  DownloadQueueItem _normalizeRestoredQueueItem(DownloadQueueItem item) {
    if (item.status == QueueItemStatus.analyzing ||
        item.status == QueueItemStatus.downloading ||
        item.status == QueueItemStatus.converting ||
        item.status == QueueItemStatus.publishing) {
      item.status = QueueItemStatus.waiting;
      item.progress = null;
      item.error = 'Interrupted before completion.';
    }
    return item;
  }

  double _restoredQueueProgress() {
    if (_queueItems.isEmpty) {
      return 0;
    }
    final done = _queueItems
        .where(
          (item) =>
              item.status == QueueItemStatus.completed ||
              item.status == QueueItemStatus.failed ||
              item.status == QueueItemStatus.skipped ||
              item.status == QueueItemStatus.cancelled,
        )
        .length;
    return done / _queueItems.length;
  }

  Future<EngineInfo> _readAndroidEngineInfo() async {
    final info = await _androidDownloaderChannel
        .invokeMethod<Map<dynamic, dynamic>>('getEngineStatus');
    return EngineInfo.fromAndroid(info);
  }

  Future<EngineInfo> _readDesktopEngineInfo() async {
    final ytDlpNames = Platform.isWindows ? ['yt-dlp.exe'] : ['yt-dlp'];
    final ffmpegNames = Platform.isWindows ? ['ffmpeg.exe'] : ['ffmpeg'];
    final ytDlp = await _findTool(ytDlpNames);
    final ffmpeg = await _findTool(ffmpegNames);

    if (ytDlp == null || ffmpeg == null) {
      return EngineInfo(
        platformLabel: _platformLabel(),
        status: ytDlp == null ? 'yt-dlp missing' : 'FFmpeg missing',
        ytDlpAvailable: ytDlp != null,
        ffmpegAvailable: ffmpeg != null,
        ytDlpVersion: ytDlp == null
            ? 'Missing'
            : await _readToolVersion(ytDlp.path),
        ffmpegVersion: ffmpeg == null
            ? 'Missing'
            : await _readToolVersion(ffmpeg.path),
        activeEnginePath: ytDlp?.path ?? ffmpeg?.path ?? 'Unavailable',
        androidUpdateStatus: 'N/A',
        ffmpegPath: ffmpeg?.path,
        ffmpegExecutionTest: ffmpeg == null ? null : 'Available',
        androidAbi: null,
        videoMergeSupported: ffmpeg != null,
      );
    }

    return EngineInfo(
      platformLabel: _platformLabel(),
      status: 'Ready',
      ytDlpAvailable: true,
      ffmpegAvailable: true,
      ytDlpVersion: await _readToolVersion(ytDlp.path),
      ffmpegVersion: await _readToolVersion(ffmpeg.path),
      activeEnginePath: ytDlp.path,
      androidUpdateStatus: 'N/A',
      ffmpegPath: ffmpeg.path,
      ffmpegExecutionTest: 'Available',
      androidAbi: null,
      videoMergeSupported: true,
    );
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim();
    final url = _extractFirstUrl(text ?? '');
    if (url == null) {
      _setStage(DownloadStage.waiting, 'Clipboard does not contain a URL.');
      return;
    }
    _setUrlInput(url, message: 'URL pasted from clipboard');
  }

  void _onUrlChanged(String value) {
    setState(() {
      _playlistInfo = null;
      _lastAnalyzedUrl = null;
      _incomingUrlMessage = null;
    });
    _scheduleUrlAnalysis(value);
  }

  void _scheduleUrlAnalysis(String value) {
    _analysisTimer?.cancel();
    final url = _extractFirstUrl(value) ?? value.trim();
    if (!_looksLikeUrl(url) || _isRunning) {
      return;
    }
    _analysisTimer = Timer(const Duration(milliseconds: 650), () {
      unawaited(_analyzeUrl(url));
    });
  }

  Future<void> _analyzeUrl(String url) async {
    final inputUrl = _extractFirstUrl(url) ?? url.trim();
    if (_isRunning || !_looksLikeUrl(inputUrl)) {
      return;
    }
    final token = inputUrl;
    setState(() {
      _playlistInfo = PlaylistInfo(
        sourceUrl: inputUrl,
        status: UrlAnalysisStatus.analyzing,
      );
      _lastAnalyzedUrl = token;
    });

    try {
      final intake = await _resolveUrlIntake(inputUrl);
      if (mounted && _lastAnalyzedUrl == token) {
        setState(() {
          _playlistInfo = intake.info;
        });
      }
    } on Object catch (error) {
      if (mounted && _lastAnalyzedUrl == token) {
        setState(() {
          _playlistInfo = PlaylistInfo(
            sourceUrl: inputUrl,
            status: UrlAnalysisStatus.unsupported,
            error: _friendlyException(error),
          );
        });
      }
    }
  }

  Future<UrlIntakeResult> _resolveUrlIntake(String rawUrl) async {
    final originalUrl = _extractFirstUrl(rawUrl) ?? rawUrl.trim();
    if (!_looksLikeUrl(originalUrl)) {
      throw StateError(
        'Enter a complete URL starting with http:// or https://.',
      );
    }

    final redirectedUrl = _smartUrlCleaning
        ? (_facebookRedirectTarget(originalUrl) ?? originalUrl)
        : originalUrl;
    final cleanedUrl = _smartUrlCleaning
        ? _cleanTrackingUrl(redirectedUrl)
        : redirectedUrl;
    final platform = _detectPlatform(cleanedUrl);
    final candidates = <String>[
      if (_smartUrlCleaning && cleanedUrl != originalUrl) cleanedUrl,
      originalUrl,
    ];

    String? cleanedError;
    Object? lastError;
    for (final candidate in candidates) {
      try {
        final rawJson = await _analyzeRawUrl(candidate);
        final info = _playlistInfoFromJson(candidate, rawJson);
        return UrlIntakeResult(
          originalUrl: originalUrl,
          cleanedUrl: cleanedUrl,
          workingUrl: candidate,
          platform: platform,
          info: info,
          cleanedAttempted: cleanedUrl != originalUrl,
          usedOriginalFallback:
              candidate == originalUrl && cleanedUrl != originalUrl,
          cleanedError: cleanedError,
        );
      } on Object catch (error) {
        lastError = error;
        if (candidate == cleanedUrl && cleanedUrl != originalUrl) {
          cleanedError = _friendlyException(error);
        }
      }
    }

    throw StateError(
      _friendlyException(lastError ?? 'This URL is not supported.'),
    );
  }

  Future<String> _analyzeRawUrl(String url) {
    return Platform.isAndroid
        ? _analyzeAndroidUrl(url)
        : _analyzeDesktopUrl(url);
  }

  Future<String> _analyzeAndroidUrl(String url) async {
    final result = await _androidDownloaderChannel
        .invokeMethod<Map<dynamic, dynamic>>('analyzeUrl', {'url': url});
    if (result?['status'] == 'ok') {
      return result?['json']?.toString() ?? '{}';
    }
    throw StateError(result?['error']?.toString() ?? 'Unsupported URL.');
  }

  Future<void> _loadInitialSharedContent() async {
    try {
      final payload = await _androidDownloaderChannel
          .invokeMethod<Map<dynamic, dynamic>>('getInitialSharedContent');
      await _handleSharedContent(payload);
    } on Object {
      // Sharing is a convenience path; normal launch should stay quiet.
    }
  }

  Future<void> _handleSharedContent(Map<dynamic, dynamic>? payload) async {
    if (payload == null || !mounted) {
      return;
    }

    final status = payload['status']?.toString();
    final text = payload['url']?.toString().trim().isNotEmpty == true
        ? payload['url'].toString()
        : payload['text']?.toString() ?? '';
    final url = _extractFirstUrl(text);

    if (status == 'empty' || url == null) {
      _setStage(
        DownloadStage.waiting,
        payload['message']?.toString() ?? 'No URL was found in shared text.',
      );
      setState(() => _incomingUrlMessage = null);
      return;
    }

    _setUrlInput(
      url,
      message:
          payload['message']?.toString() ?? 'URL received from another app',
      analyzeNow: !_isRunning,
    );
    if (_isRunning) {
      _setStage(
        _stage,
        'URL received from another app and placed in the input field for later.',
      );
    }
  }

  void _setUrlInput(
    String url, {
    required String message,
    bool analyzeNow = true,
  }) {
    _urlController.text = url;
    _urlController.selection = TextSelection.collapsed(offset: url.length);
    _analysisTimer?.cancel();
    setState(() {
      _incomingUrlMessage = message;
      _playlistInfo = null;
      _lastAnalyzedUrl = null;
    });
    if (analyzeNow) {
      _scheduleUrlAnalysis(url);
    }
  }

  Future<String> _analyzeDesktopUrl(String url) async {
    final tools = await _resolveTools();
    final result = await Process.run(tools.ytDlp, [
      '--dump-single-json',
      '--flat-playlist',
      '--skip-download',
      '--no-warnings',
      url,
    ], runInShell: false).timeout(const Duration(seconds: 45));

    if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
      return result.stdout.toString();
    }
    throw StateError(
      result.stderr.toString().trim().isEmpty
          ? 'Unsupported URL or site.'
          : result.stderr.toString().trim(),
    );
  }

  PlaylistInfo _playlistInfoFromJson(String sourceUrl, String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('yt-dlp returned an unreadable response.');
    }

    final entriesRaw = decoded['entries'];
    final entries = <PlaylistEntry>[];
    if (entriesRaw is List) {
      for (var i = 0; i < entriesRaw.length; i += 1) {
        final entry = entriesRaw[i];
        if (entry is! Map) {
          continue;
        }
        final entryUrl = _playlistEntryUrl(entry);
        if (entryUrl == null || entryUrl.isEmpty) {
          continue;
        }
        final title = _bestTitle(entry, fallback: 'Item ${i + 1}');
        entries.add(PlaylistEntry(title: title, url: entryUrl, index: i + 1));
      }
    }

    final type = decoded['_type']?.toString().toLowerCase();
    final total =
        int.tryParse(
          decoded['playlist_count']?.toString() ??
              decoded['n_entries']?.toString() ??
              '',
        ) ??
        (entries.isEmpty ? null : entries.length);

    if (type == 'playlist' || entries.isNotEmpty) {
      return PlaylistInfo(
        sourceUrl: sourceUrl,
        status: UrlAnalysisStatus.playlist,
        title: _bestTitle(decoded, fallback: 'Playlist'),
        totalCount: total,
        items: entries,
      );
    }

    return PlaylistInfo(
      sourceUrl: sourceUrl,
      status: UrlAnalysisStatus.single,
      title: _bestTitle(decoded, fallback: 'Single media'),
      totalCount: 1,
    );
  }

  String _bestTitle(Map<dynamic, dynamic> value, {required String fallback}) {
    return (value['title'] ??
            value['fulltitle'] ??
            value['playlist_title'] ??
            value['id'] ??
            fallback)
        .toString()
        .trim();
  }

  String? _playlistEntryUrl(Map<dynamic, dynamic> entry) {
    final webpageUrl = entry['webpage_url']?.toString();
    if (webpageUrl != null && _looksLikeUrl(webpageUrl)) {
      return webpageUrl;
    }
    final url = entry['url']?.toString();
    if (url == null || url.isEmpty) {
      return null;
    }
    if (_looksLikeUrl(url)) {
      return url;
    }
    final extractor = (entry['ie_key'] ?? entry['extractor_key'] ?? '')
        .toString()
        .toLowerCase();
    if (extractor.contains('youtube') || RegExp(r'^[\w-]{8,}$').hasMatch(url)) {
      return 'https://www.youtube.com/watch?v=$url';
    }
    return url;
  }

  Future<String?> _chooseDownloadFolder() async {
    if (_isRunning) {
      return null;
    }

    String? folder;
    try {
      folder = await getDirectoryPath(
        initialDirectory: _outputFolder,
        confirmButtonText: 'Use folder',
      );
    } on Object catch (error) {
      _setStage(
        DownloadStage.failed,
        Platform.isAndroid
            ? 'Folder picker is not available on this device.'
            : _friendlyException(error),
      );
      return null;
    }

    if (folder == null || folder.isEmpty) {
      return null;
    }

    final validation = await _validateDownloadFolder(folder);
    if (validation != null) {
      _setStage(DownloadStage.failed, validation);
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadFolderPreference, folder);
    if (mounted) {
      setState(() => _outputFolder = folder);
    }
    return folder;
  }

  Future<String?> _validateDownloadFolder(String folder) async {
    if (Platform.isAndroid) {
      return _androidRelativeDownloadFolder(folder) == null
          ? 'Android can save to folders inside Downloads only.'
          : null;
    }

    try {
      final directory = Directory(folder);
      await directory.create(recursive: true);
      final probe = File(
        _joinPath(
          folder,
          '.down_any_media_write_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } on Object {
      return 'Folder is not writable.';
    }
  }

  Future<void> _openCurrentDownloadFolder() async {
    final folder = _outputFolder ?? await _resolveDefaultDownloadFolder();
    if (Platform.isAndroid) {
      try {
        final opened = await _androidDownloaderChannel.invokeMethod<bool>(
          'openFolder',
          {'folderPath': folder},
        );
        if (opened != true) {
          _setStage(
            DownloadStage.waiting,
            'Download folder: ${_simplePath(folder)}',
          );
        }
      } on Object catch (error) {
        _rememberLog('Could not open download folder: $error');
        _setStage(DownloadStage.failed, 'Could not open folder.');
      }
      return;
    }
    await Directory(folder).create(recursive: true);
    await _openPath(folder);
  }

  Future<void> _setPlaylistFilenameStyle(PlaylistFilenameStyle value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistFilenameStylePreference, value.name);
    if (mounted) {
      setState(() => _playlistFilenameStyle = value);
    }
  }

  Future<void> _setEmbedMetadata(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_embedMetadataPreference, value);
    if (mounted) {
      setState(() => _embedMetadata = value);
    }
  }

  Future<void> _setEmbedThumbnail(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_embedThumbnailPreference, value);
    if (mounted) {
      setState(() => _embedThumbnail = value);
    }
  }

  Future<void> _setSmartUrlCleaning(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_smartUrlCleaningPreference, value);
    if (mounted) {
      setState(() => _smartUrlCleaning = value);
    }
  }

  Future<void> _setAudioQualityPreset(AudioQualityPreset value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioQualityPreference, value.name);
    if (mounted) {
      setState(() => _audioQualityPreset = value);
    }
  }

  Future<void> _setDownloadMode(DownloadMode value) async {
    if (mounted) {
      setState(() => _downloadMode = value);
    }
  }

  Future<void> _setVideoQualityPreset(VideoQualityPreset value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoQualityPreference, value.name);
    if (mounted) {
      setState(() => _videoQualityPreset = value);
    }
  }

  Future<void> _startDownload() async {
    final rawInput = _urlController.text.trim();
    if (rawInput.isEmpty) {
      _setStage(
        DownloadStage.failed,
        'Paste or share a URL before downloading.',
      );
      return;
    }
    final url = _extractFirstUrl(rawInput) ?? rawInput;
    if (!_looksLikeUrl(url)) {
      _setStage(
        DownloadStage.failed,
        'Enter a complete URL starting with http:// or https://.',
      );
      return;
    }
    if (_isRunning) {
      return;
    }
    if (url != rawInput) {
      _urlController.text = url;
      _urlController.selection = TextSelection.collapsed(offset: url.length);
    }

    final outputFolder = _outputFolder ?? await _resolveDefaultDownloadFolder();
    _outputFolder = outputFolder;

    setState(() {
      _stage = DownloadStage.analyzing;
      _progress = null;
      _totalProgress = null;
      _speed = null;
      _eta = null;
      _message = 'Preparing download...';
      _recentLogLines.clear();
      _queueItems.clear();
      _activeQueueIndex = -1;
      _queueTitle = null;
      _cancelRequested = false;
      _queueCancelRequested = false;
    });
    await _saveQueueState();

    try {
      _setStage(DownloadStage.analyzing, 'Checking media link...');
      final intake = await _resolveUrlIntake(url);
      final info = intake.info;
      if (info.status == UrlAnalysisStatus.unsupported ||
          info.status == UrlAnalysisStatus.failed) {
        _setStage(
          DownloadStage.failed,
          info.error ?? 'This URL is not supported.',
        );
        return;
      }

      if (info.isPlaylist && info.items.isNotEmpty) {
        await _startPlaylistQueue(info);
        return;
      }

      final singleBaseName = _sanitizeName(info.title ?? 'download');
      final outputBaseName = Platform.isAndroid
          ? singleBaseName
          : await _uniqueDesktopBaseName(outputFolder, singleBaseName);
      Future<DownloadOutcome> runSingleDownload(String downloadUrl) {
        return Platform.isAndroid
            ? _runAndroidDownload(
                downloadUrl,
                outputFolder: outputFolder,
                outputBaseName: singleBaseName,
                notificationTitle: info.title ?? singleBaseName,
                downloadMode: _downloadMode,
                videoQuality: _videoQualityPreset,
              )
            : _runDesktopDownload(
                url: downloadUrl,
                outputFolder: outputFolder,
                outputBaseName: outputBaseName,
                downloadMode: _downloadMode,
                videoQuality: _videoQualityPreset,
              );
      }

      var outcome = await runSingleDownload(intake.workingUrl);
      if (!outcome.success &&
          !outcome.cancelled &&
          intake.cleanedWorked &&
          intake.cleanedChanged) {
        _rememberLog('Retrying with original URL after cleaned URL failed.');
        outcome = await runSingleDownload(intake.originalUrl);
      }

      if (outcome.cancelled || _cancelRequested) {
        _setStage(DownloadStage.cancelled, 'Download cancelled.');
        return;
      }

      if (outcome.success && outcome.filePath != null) {
        await _addCompletedDownload(
          fileName: outcome.fileName ?? _fileName(outcome.filePath!),
          filePath: outcome.filePath!,
          contentUri: outcome.contentUri,
          downloadMode: _downloadMode,
          videoQualityLabel: _downloadMode == DownloadMode.video
              ? _videoQualityPreset.label
              : null,
        );
        _setStage(
          DownloadStage.completed,
          outcome.warning ??
              (_downloadMode == DownloadMode.video
                  ? 'Video saved successfully.'
                  : 'Audio saved successfully.'),
        );
      } else {
        final failedItem = DownloadQueueItem(
          title: info.title ?? 'Download',
          url: url,
          index: 1,
          status: QueueItemStatus.failed,
          downloadMode: _downloadMode,
          videoQuality: _downloadMode == DownloadMode.video
              ? _videoQualityPreset
              : null,
        )..error = outcome.error ?? 'Download failed.';
        setState(() {
          _queueTitle = 'Single download';
          _queueOutputFolder = outputFolder;
          _queueCreatedAt = DateTime.now();
          _queueItems
            ..clear()
            ..add(failedItem);
          _activeQueueIndex = -1;
          _queuePaused = true;
        });
        await _saveQueueState();
        _setStage(DownloadStage.failed, outcome.error ?? 'Download failed.');
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _downloadProcess = null);
      final summary = _friendlyException(error);
      _setStage(DownloadStage.failed, summary);
      await _refreshEngineStatus();
    }
  }

  Future<void> _startPlaylistQueue(PlaylistInfo playlist) async {
    final title = playlist.title?.trim().isNotEmpty == true
        ? playlist.title!.trim()
        : _playlistFallbackName();
    final folderName = _sanitizeName(title);
    final rootFolder = _outputFolder ?? await _resolveDefaultDownloadFolder();
    final playlistFolder = _joinPath(rootFolder, folderName);

    final items = playlist.items
        .map(
          (entry) => DownloadQueueItem(
            title: entry.title,
            url: entry.url,
            index: entry.index,
            downloadMode: _downloadMode,
            videoQuality: _downloadMode == DownloadMode.video
                ? _videoQualityPreset
                : null,
          ),
        )
        .toList();

    setState(() {
      _queueTitle = title;
      _queueItems
        ..clear()
        ..addAll(items);
      _activeQueueIndex = -1;
      _totalProgress = 0;
      _queueOutputFolder = playlistFolder;
      _queueCreatedAt = DateTime.now();
      _queuePaused = false;
      _queuePauseRequested = false;
      _message = 'Queued ${items.length} playlist items.';
    });
    await _saveQueueState();

    var completed = 0;
    var failed = 0;
    var skipped = 0;

    for (var i = 0; i < _queueItems.length; i += 1) {
      if (_queueCancelRequested || _cancelRequested || _queuePauseRequested) {
        for (var j = i; j < _queueItems.length; j += 1) {
          if (!_queuePauseRequested) {
            _queueItems[j].status = QueueItemStatus.cancelled;
          }
        }
        await _saveQueueState();
        break;
      }

      final item = _queueItems[i];
      if (!_looksLikeUrl(item.url)) {
        item.status = QueueItemStatus.skipped;
        item.error = 'Unsupported item URL.';
        skipped += 1;
        _updateQueueProgress();
        unawaited(_saveQueueState());
        continue;
      }

      setState(() {
        _activeQueueIndex = i;
        item.status = QueueItemStatus.analyzing;
        item.progress = null;
        _stage = DownloadStage.analyzing;
        _progress = null;
        _speed = null;
        _eta = null;
        _message = 'Starting ${item.title} (${i + 1}/${_queueItems.length})';
      });
      await _saveQueueState();

      final baseTitle = _sanitizeName(item.title);
      final baseName =
          _playlistFilenameStyle == PlaylistFilenameStyle.numberedPlaylistOrder
          ? '${(i + 1).toString().padLeft(2, '0')} - $baseTitle'
          : baseTitle;

      late final UrlIntakeResult intake;
      try {
        intake = await _resolveUrlIntake(item.url);
      } on Object catch (error) {
        item.status = QueueItemStatus.failed;
        item.error = _friendlyException(error);
        failed += 1;
        _updateQueueProgress();
        await _saveQueueState();
        continue;
      }

      final outputBaseName = Platform.isAndroid
          ? baseName
          : await _uniqueDesktopBaseName(playlistFolder, baseName);
      Future<DownloadOutcome> runQueueDownload(String downloadUrl) {
        return Platform.isAndroid
            ? _runAndroidDownload(
                downloadUrl,
                outputFolder: rootFolder,
                folderName: folderName,
                outputBaseName: baseName,
                notificationTitle: item.title,
                queueIndex: i + 1,
                queueTotal: _queueItems.length,
                downloadMode: item.downloadMode,
                videoQuality: item.videoQuality,
              )
            : _runDesktopDownload(
                url: downloadUrl,
                outputFolder: playlistFolder,
                outputBaseName: outputBaseName,
                downloadMode: item.downloadMode,
                videoQuality: item.videoQuality,
              );
      }

      var outcome = await runQueueDownload(intake.workingUrl);
      if (!outcome.success &&
          !outcome.cancelled &&
          intake.cleanedWorked &&
          intake.cleanedChanged) {
        _rememberLog('Retrying with original URL after cleaned URL failed.');
        outcome = await runQueueDownload(intake.originalUrl);
      }

      if (outcome.cancelled || _queueCancelRequested || _cancelRequested) {
        item.status = QueueItemStatus.cancelled;
        _setStage(DownloadStage.cancelled, 'Playlist download cancelled.');
        await _saveQueueState();
        break;
      }

      if (outcome.success) {
        item.status = QueueItemStatus.completed;
        item.progress = 1;
        item.filePath = outcome.filePath;
        completed += 1;
      } else {
        item.status = QueueItemStatus.failed;
        item.error = outcome.error ?? 'Download failed.';
        failed += 1;
      }
      _updateQueueProgress();
      await _saveQueueState();
    }

    if (_queuePauseRequested && !_queueCancelRequested && !_cancelRequested) {
      _queuePaused = true;
      _setStage(DownloadStage.cancelled, 'Queue paused. Resume when ready.');
      await _saveQueueState();
    } else if (!_queueCancelRequested && !_cancelRequested) {
      await _addCompletedDownload(
        fileName: title,
        filePath: playlistFolder,
        isPlaylist: true,
        totalCount: _queueItems.length,
        completedCount: completed,
        failedCount: failed,
        skippedCount: skipped,
        folderPathOverride: playlistFolder,
        downloadMode: _downloadMode,
        videoQualityLabel: _downloadMode == DownloadMode.video
            ? _videoQualityPreset.label
            : null,
      );
      _setStage(
        DownloadStage.completed,
        'Playlist finished: $completed completed, $failed failed, $skipped skipped.',
      );
      await _saveQueueState();
    }

    if (mounted) {
      setState(() => _activeQueueIndex = -1);
    }
  }

  void _updateQueueProgress() {
    final done = _queueItems.where((item) {
      return item.status == QueueItemStatus.completed ||
          item.status == QueueItemStatus.failed ||
          item.status == QueueItemStatus.skipped ||
          item.status == QueueItemStatus.cancelled;
    }).length;
    final current =
        _activeQueueIndex >= 0 && _activeQueueIndex < _queueItems.length
        ? (_queueItems[_activeQueueIndex].progress ?? 0)
        : 0;
    setState(() {
      _totalProgress = _queueItems.isEmpty
          ? null
          : ((done + current).clamp(0, _queueItems.length)) /
                _queueItems.length;
    });
  }

  Future<void> _resumeQueue() async {
    if (_isRunning || _queueItems.isEmpty) {
      return;
    }
    if (!_queueItems.any((item) => item.status == QueueItemStatus.waiting)) {
      _setStage(DownloadStage.waiting, 'No pending queue items to resume.');
      return;
    }
    await _processSavedQueue();
  }

  Future<void> _retryFailedQueue() async {
    if (_isRunning || _queueItems.isEmpty) {
      return;
    }
    final failedItems = _queueItems.where(
      (item) => item.status == QueueItemStatus.failed,
    );
    if (failedItems.isEmpty) {
      _setStage(DownloadStage.waiting, 'No failed queue items to retry.');
      return;
    }
    for (final item in failedItems) {
      item.status = QueueItemStatus.waiting;
      item.progress = null;
      item.error = null;
    }
    await _saveQueueState();
    await _processSavedQueue();
  }

  Future<void> _pauseQueue() async {
    if (_queueItems.isEmpty) {
      return;
    }
    _queuePauseRequested = true;
    if (_isRunning) {
      await _cancelDownload();
      return;
    }
    setState(() {
      _queuePaused = true;
      _message = 'Queue paused.';
    });
    await _saveQueueState();
  }

  Future<void> _cancelAllQueue() async {
    if (_queueItems.isEmpty) {
      return;
    }
    _queueCancelRequested = true;
    if (_isRunning) {
      await _cancelDownload();
    }
    setState(() {
      for (final item in _queueItems) {
        if (item.status == QueueItemStatus.waiting ||
            item.status == QueueItemStatus.analyzing ||
            item.status == QueueItemStatus.downloading ||
            item.status == QueueItemStatus.converting ||
            item.status == QueueItemStatus.publishing) {
          item.status = QueueItemStatus.cancelled;
          item.progress = null;
        }
      }
      _activeQueueIndex = -1;
      _queuePaused = false;
      _message = 'Queue cancelled. Completed files were kept.';
    });
    _updateQueueProgress();
    await _saveQueueState();
  }

  Future<void> _processSavedQueue() async {
    final playlistFolder =
        _queueOutputFolder ??
        _outputFolder ??
        await _resolveDefaultDownloadFolder();
    final folderName = _sanitizeName(_queueTitle ?? _playlistFallbackName());

    setState(() {
      _queuePaused = false;
      _queuePauseRequested = false;
      _queueCancelRequested = false;
      _cancelRequested = false;
      _queueOutputFolder = playlistFolder;
      _queueCreatedAt ??= DateTime.now();
      _message = 'Resuming queue...';
    });
    await _saveQueueState();

    for (var i = 0; i < _queueItems.length; i += 1) {
      final item = _queueItems[i];
      if (item.status != QueueItemStatus.waiting) {
        continue;
      }
      if (_queueCancelRequested || _cancelRequested || _queuePauseRequested) {
        break;
      }
      if (!_looksLikeUrl(item.url)) {
        item.status = QueueItemStatus.skipped;
        item.error = 'Unsupported item URL.';
        _updateQueueProgress();
        await _saveQueueState();
        continue;
      }

      setState(() {
        _activeQueueIndex = i;
        item.status = QueueItemStatus.analyzing;
        item.progress = null;
        item.error = null;
        _stage = DownloadStage.analyzing;
        _progress = null;
        _speed = null;
        _eta = null;
        _message = 'Starting ${item.title} (${i + 1}/${_queueItems.length})';
      });
      await _saveQueueState();

      final baseTitle = _sanitizeName(item.title);
      final baseName =
          _playlistFilenameStyle == PlaylistFilenameStyle.numberedPlaylistOrder
          ? '${(i + 1).toString().padLeft(2, '0')} - $baseTitle'
          : baseTitle;

      late final UrlIntakeResult intake;
      try {
        intake = await _resolveUrlIntake(item.url);
      } on Object catch (error) {
        item.status = QueueItemStatus.failed;
        item.error = _friendlyException(error);
        _updateQueueProgress();
        await _saveQueueState();
        continue;
      }

      final outputBaseName = Platform.isAndroid
          ? baseName
          : await _uniqueDesktopBaseName(playlistFolder, baseName);
      Future<DownloadOutcome> runQueueDownload(String downloadUrl) {
        return Platform.isAndroid
            ? _runAndroidDownload(
                downloadUrl,
                outputFolder: _parentFolderForQueue(playlistFolder, folderName),
                folderName: folderName,
                outputBaseName: baseName,
                notificationTitle: item.title,
                queueIndex: i + 1,
                queueTotal: _queueItems.length,
                downloadMode: item.downloadMode,
                videoQuality: item.videoQuality,
              )
            : _runDesktopDownload(
                url: downloadUrl,
                outputFolder: playlistFolder,
                outputBaseName: outputBaseName,
                downloadMode: item.downloadMode,
                videoQuality: item.videoQuality,
              );
      }

      var outcome = await runQueueDownload(intake.workingUrl);
      if (!outcome.success &&
          !outcome.cancelled &&
          intake.cleanedWorked &&
          intake.cleanedChanged) {
        _rememberLog('Retrying with original URL after cleaned URL failed.');
        outcome = await runQueueDownload(intake.originalUrl);
      }

      if (outcome.cancelled || _cancelRequested || _queueCancelRequested) {
        item.status = QueueItemStatus.cancelled;
        item.progress = null;
        _setStage(DownloadStage.cancelled, 'Current queue item cancelled.');
        await _saveQueueState();
        break;
      }

      if (outcome.success) {
        item.status = QueueItemStatus.completed;
        item.progress = 1;
        item.filePath = outcome.filePath;
      } else {
        item.status = QueueItemStatus.failed;
        item.error = outcome.error ?? 'Download failed.';
      }
      _updateQueueProgress();
      await _saveQueueState();
    }

    if (_queuePauseRequested) {
      setState(() {
        _queuePaused = true;
        _activeQueueIndex = -1;
      });
      _setStage(DownloadStage.cancelled, 'Queue paused. Resume when ready.');
      await _saveQueueState();
      return;
    }

    final pending = _queueItems
        .where((item) => item.status == QueueItemStatus.waiting)
        .length;
    final completed = _queueItems
        .where((item) => item.status == QueueItemStatus.completed)
        .length;
    final failed = _queueItems
        .where((item) => item.status == QueueItemStatus.failed)
        .length;
    final skipped = _queueItems
        .where((item) => item.status == QueueItemStatus.skipped)
        .length;
    if (pending == 0 && !_queueCancelRequested && !_cancelRequested) {
      await _addCompletedDownload(
        fileName: _queueTitle ?? 'Queue',
        filePath: playlistFolder,
        isPlaylist: true,
        totalCount: _queueItems.length,
        completedCount: completed,
        failedCount: failed,
        skippedCount: skipped,
        folderPathOverride: playlistFolder,
        downloadMode:
            _queueItems.any((item) => item.downloadMode == DownloadMode.video)
            ? DownloadMode.video
            : DownloadMode.mp3,
        videoQualityLabel: _queueVideoQualityLabel(),
      );
      _setStage(
        DownloadStage.completed,
        'Queue finished: $completed completed, $failed failed, $skipped skipped.',
      );
    }
    if (mounted) {
      setState(() => _activeQueueIndex = -1);
    }
    await _saveQueueState();
  }

  String? _queueVideoQualityLabel() {
    for (final item in _queueItems) {
      if (item.downloadMode == DownloadMode.video &&
          item.videoQuality != null) {
        return item.videoQuality!.label;
      }
    }
    return null;
  }

  Future<void> _cancelDownload() async {
    final androidProcessId = _androidProcessId;
    if (androidProcessId != null) {
      _cancelRequested = true;
      _setStage(DownloadStage.cancelled, 'Stopping download...');
      await _androidDownloaderChannel.invokeMethod<bool>('cancelDownload', {
        'processId': androidProcessId,
      });
      return;
    }

    final process = _downloadProcess;
    if (process == null) {
      return;
    }
    _cancelRequested = true;
    _setStage(DownloadStage.cancelled, 'Stopping download...');
    process.kill();

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_downloadProcess == process) {
        process.kill(ProcessSignal.sigkill);
      }
    });
  }

  Future<void> _openFile(CompletedDownload item) async {
    if (Platform.isAndroid) {
      await _invokeAndroidOpen('openFile', item);
      return;
    }
    await _openPath(item.filePath);
  }

  Future<void> _openFolder(CompletedDownload item) async {
    if (Platform.isAndroid) {
      await _invokeAndroidOpen('openFolder', item);
      return;
    }
    await _openPath(item.folderPath);
  }

  Future<void> _invokeAndroidOpen(String method, CompletedDownload item) async {
    try {
      final opened = await _androidDownloaderChannel
          .invokeMethod<bool>(method, {
            'filePath': item.filePath,
            'folderPath': item.folderPath,
            'contentUri': item.contentUri,
          });
      if (opened != true) {
        _setStage(
          DownloadStage.failed,
          method == 'openFile'
              ? 'Could not open file.'
              : 'Could not open folder.',
        );
      }
    } on Object catch (error) {
      _rememberLog('Could not open Android path: $error');
      _setStage(
        DownloadStage.failed,
        method == 'openFile'
            ? 'Could not open file.'
            : 'Could not open folder.',
      );
    }
  }

  Future<void> _openPath(String path, {bool selectFile = false}) async {
    try {
      if (Platform.isWindows) {
        if (selectFile) {
          await Process.start('explorer.exe', ['/select,$path']);
        } else if (FileSystemEntity.isFileSync(path)) {
          await Process.start('cmd.exe', ['/c', 'start', '', path]);
        } else {
          await Process.start('explorer.exe', [path]);
        }
        return;
      }

      if (Platform.isLinux) {
        await Process.start('xdg-open', [
          selectFile ? File(path).parent.path : path,
        ]);
        return;
      }

      _setStage(DownloadStage.waiting, 'Saved at ${_simplePath(path)}');
    } on Object catch (error) {
      _rememberLog('Could not open path: $error');
      _setStage(
        DownloadStage.failed,
        FileSystemEntity.isFileSync(path)
            ? 'Could not open file.'
            : 'Could not open folder.',
      );
    }
  }

  Future<void> _listenToProcessOutput(Stream<List<int>> output) async {
    await for (final line
        in output.transform(utf8.decoder).transform(const LineSplitter())) {
      _handleProcessLine(line);
    }
  }

  Future<DownloadOutcome> _runDesktopDownload({
    required String url,
    required String outputFolder,
    String? outputBaseName,
    DownloadMode downloadMode = DownloadMode.mp3,
    VideoQualityPreset? videoQuality,
  }) async {
    final startedAt = DateTime.now();
    final tools = await _resolveTools();
    await Directory(outputFolder).create(recursive: true);
    final taskId =
        '${downloadMode == DownloadMode.mp3 ? 'mp3' : 'video'}_${startedAt.microsecondsSinceEpoch}';

    final outputTemplate = outputBaseName == null || outputBaseName.isEmpty
        ? _joinPath(outputFolder, '%(title).200s-$taskId.%(ext)s')
        : _joinPath(outputFolder, '$outputBaseName-$taskId.%(ext)s');

    final args = <String>[
      '--newline',
      '--no-warnings',
      '--no-playlist',
      '-o',
      outputTemplate,
    ];

    if (downloadMode == DownloadMode.mp3) {
      args.addAll([
        '-x',
        '-f',
        'bestaudio/best',
        '--audio-format',
        'mp3',
        '--audio-quality',
        _audioQualityPreset.ytDlpValue,
      ]);
      if (_embedMetadata) {
        args.add('--embed-metadata');
      }
      if (_embedThumbnail) {
        args.add('--embed-thumbnail');
      }
    }

    if (tools.ffmpegIsBundled) {
      args.addAll(['--ffmpeg-location', File(tools.ffmpeg).parent.path]);
    }

    var fallbackAttempted = false;
    var selectedFormat = downloadMode == DownloadMode.mp3
        ? 'bestaudio/best'
        : (videoQuality ?? VideoQualityPreset.best).formatSelector;
    final fallbackStepsTried = <String>[];
    var exitCode = 1;
    File? outputFile;

    final attempts = downloadMode == DownloadMode.video
        ? _videoFormatAttempts(videoQuality)
        : const <String?>[null];

    for (
      var attemptIndex = 0;
      attemptIndex < attempts.length;
      attemptIndex += 1
    ) {
      final format = attempts[attemptIndex];
      final attemptArgs = List<String>.from(args);
      if (downloadMode == DownloadMode.video && format != null) {
        selectedFormat = format;
        fallbackStepsTried.add(format);
        attemptArgs.addAll(['-f', format]);
        attemptArgs.addAll(['--merge-output-format', 'mp4']);
        if (attemptIndex > 0) {
          fallbackAttempted = true;
          _rememberLog('Retrying video with fallback format: $format');
        }
      } else if (downloadMode == DownloadMode.video) {
        selectedFormat = 'automatic';
        fallbackStepsTried.add('automatic');
        fallbackAttempted = true;
        _rememberLog('Retrying video with automatic format selection.');
      }
      attemptArgs.add(url);

      final process = await Process.start(
        tools.ytDlp,
        attemptArgs,
        runInShell: false,
      );

      setState(() {
        _downloadProcess = process;
        _message = downloadMode == DownloadMode.video
            ? (attemptIndex == 0
                  ? 'Downloading video...'
                  : 'Retrying with best available video...')
            : 'Checking media link...';
      });

      final stdoutDone = _listenToProcessOutput(process.stdout);
      final stderrDone = _listenToProcessOutput(process.stderr);
      exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);

      outputFile = await _findNewestMedia(
        outputFolder,
        startedAt,
        downloadMode,
        taskId: taskId,
      );

      if (_cancelRequested) {
        break;
      }
      if (exitCode == 0 && outputFile != null) {
        break;
      }
      if (downloadMode == DownloadMode.mp3) {
        break;
      }
    }

    if (mounted) {
      setState(() => _downloadProcess = null);
    }

    if (_cancelRequested) {
      return const DownloadOutcome(success: false, cancelled: true);
    }

    if (exitCode == 0 && outputFile != null) {
      return DownloadOutcome(
        success: true,
        fileName: _fileName(outputFile.path),
        filePath: outputFile.path,
        selectedFormat: selectedFormat,
        fallbackStepsTried: fallbackStepsTried,
        finalFilePath: outputFile.path,
        tempFolder: outputFolder,
        publishResult: 'Saved directly',
        fallbackAttempted: fallbackAttempted,
        warning: downloadMode == DownloadMode.video && fallbackAttempted
            ? 'Video saved using the best available fallback format.'
            : null,
      );
    }

    if (downloadMode == DownloadMode.mp3 &&
        outputFile != null &&
        _looksLikeOptionalMetadataFailure()) {
      return DownloadOutcome(
        success: true,
        fileName: _fileName(outputFile.path),
        filePath: outputFile.path,
        selectedFormat: selectedFormat,
        fallbackStepsTried: fallbackStepsTried,
        finalFilePath: outputFile.path,
        tempFolder: outputFolder,
        publishResult: 'Saved directly',
        fallbackAttempted: fallbackAttempted,
        warning: 'Audio saved. Some optional details could not be added.',
      );
    }

    return DownloadOutcome(
      success: false,
      error: _readableFailureMessage(exitCode),
      selectedFormat: selectedFormat,
      fallbackStepsTried: fallbackStepsTried,
      tempFolder: outputFolder,
      publishResult: 'Not published',
      fallbackAttempted: fallbackAttempted,
    );
  }

  List<String?> _videoFormatAttempts(VideoQualityPreset? videoQuality) {
    final selected = (videoQuality ?? VideoQualityPreset.best).formatSelector;
    final attempts = <String?>[selected, 'bv*+ba/best', 'best', null];
    return attempts.toSet().toList();
  }

  List<String> _stringListFrom(Object? value) {
    return value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const [];
  }

  Future<DownloadOutcome> _runAndroidDownload(
    String url, {
    String? outputFolder,
    String? folderName,
    String? outputBaseName,
    String? notificationTitle,
    int? queueIndex,
    int? queueTotal,
    DownloadMode downloadMode = DownloadMode.mp3,
    VideoQualityPreset? videoQuality,
  }) async {
    final startedAt = DateTime.now();
    final processId =
        '${downloadMode == DownloadMode.mp3 ? 'mp3' : 'video'}_${startedAt.microsecondsSinceEpoch}';

    setState(() {
      _androidProcessId = processId;
      _stage = DownloadStage.updatingEngine;
      _message = 'Preparing Download Engine...';
    });

    try {
      final arguments = <String, Object>{'url': url, 'processId': processId};
      arguments['downloadMode'] = downloadMode.name;
      arguments['embedMetadata'] = _embedMetadata;
      arguments['embedThumbnail'] = _embedThumbnail;
      arguments['audioQuality'] = _audioQualityPreset.ytDlpValue;
      if (downloadMode == DownloadMode.video) {
        arguments['videoQuality'] =
            (videoQuality ?? VideoQualityPreset.best).name;
        arguments['videoFormatSelector'] =
            (videoQuality ?? VideoQualityPreset.best).formatSelector;
      }
      final relativeBaseFolder = _androidRelativeDownloadFolder(
        outputFolder ?? _outputFolder,
      );
      if (relativeBaseFolder != null) {
        arguments['relativeBaseFolder'] = relativeBaseFolder;
      }
      if (folderName != null) {
        arguments['folderName'] = folderName;
      }
      if (outputBaseName != null) {
        arguments['outputBaseName'] = outputBaseName;
      }
      if (notificationTitle != null) {
        arguments['notificationTitle'] = notificationTitle;
      }
      if (queueIndex != null && queueTotal != null) {
        arguments['queueIndex'] = queueIndex;
        arguments['queueTotal'] = queueTotal;
      }
      final result = await _androidDownloaderChannel
          .invokeMethod<Map<dynamic, dynamic>>('startMp3Download', arguments);

      if (!mounted || _androidProcessId != processId) {
        return const DownloadOutcome(success: false, cancelled: true);
      }

      setState(() => _androidProcessId = null);
      await _refreshEngineStatus();

      final status = result?['status']?.toString();
      bool? boolField(String key) {
        if (result?.containsKey(key) != true) {
          return null;
        }
        return result![key] == true;
      }

      final fallbackSteps = _stringListFrom(result?['fallbackStepsTried']);
      final filesFound = _stringListFrom(result?['filesFound']);
      if (_cancelRequested || status == 'cancelled') {
        return const DownloadOutcome(success: false, cancelled: true);
      }

      if (status == 'error') {
        return DownloadOutcome(
          success: false,
          error: _friendlyAndroidError(
            result?['error']?.toString() ?? 'Android download failed.',
          ),
          selectedFormat: result?['selectedFormat']?.toString(),
          fallbackStepsTried: fallbackSteps,
          tempFolder: result?['tempFolder']?.toString(),
          publishResult: result?['publishResult']?.toString(),
          ffmpegAvailable: boolField('ffmpegAvailable'),
          ffmpegPath: result?['ffmpegPath']?.toString(),
          ffmpegVersion: result?['ffmpegVersion']?.toString(),
          ffmpegExecutionTest: result?['ffmpegExecutionTest']?.toString(),
          androidAbi: result?['androidAbi']?.toString(),
          videoMergeSupported: boolField('videoMergeSupported'),
          filesFound: filesFound,
          fallbackAttempted: result?['fallbackAttempted'] == true,
        );
      }

      final filePath = result?['filePath']?.toString();
      final fileName =
          result?['fileName']?.toString() ??
          (filePath == null ? null : _fileName(filePath));
      if (status == 'completed' &&
          filePath != null &&
          filePath.isNotEmpty &&
          fileName != null) {
        return DownloadOutcome(
          success: true,
          fileName: fileName,
          filePath: filePath,
          contentUri: result?['contentUri']?.toString(),
          warning: _friendlyWarning(result?['warning']?.toString()),
          selectedFormat: result?['selectedFormat']?.toString(),
          fallbackStepsTried: fallbackSteps,
          finalFilePath: result?['finalFilePath']?.toString() ?? filePath,
          tempFolder: result?['tempFolder']?.toString(),
          publishResult: result?['publishResult']?.toString(),
          ffmpegAvailable: boolField('ffmpegAvailable'),
          ffmpegPath: result?['ffmpegPath']?.toString(),
          ffmpegVersion: result?['ffmpegVersion']?.toString(),
          ffmpegExecutionTest: result?['ffmpegExecutionTest']?.toString(),
          androidAbi: result?['androidAbi']?.toString(),
          videoMergeSupported: boolField('videoMergeSupported'),
          filesFound: filesFound,
          fallbackAttempted: result?['fallbackAttempted'] == true,
        );
      }

      return const DownloadOutcome(
        success: false,
        error: 'Android download did not return a media file.',
      );
    } on PlatformException catch (error) {
      if (!mounted || _androidProcessId != processId) {
        return const DownloadOutcome(success: false, cancelled: true);
      }
      setState(() => _androidProcessId = null);
      return DownloadOutcome(
        success: false,
        error: _friendlyAndroidError(
          error.message ?? 'Android download failed.',
        ),
        selectedFormat: videoQuality?.formatSelector,
        ffmpegAvailable: Platform.isAndroid
            ? _engineInfo.ffmpegAvailable
            : null,
        ffmpegPath: _engineInfo.ffmpegPath,
        ffmpegVersion: _engineInfo.ffmpegVersion,
        ffmpegExecutionTest: _engineInfo.ffmpegExecutionTest,
        androidAbi: _engineInfo.androidAbi,
        videoMergeSupported: _engineInfo.videoMergeSupported,
      );
    } on Object catch (error) {
      if (!mounted || _androidProcessId != processId) {
        return const DownloadOutcome(success: false, cancelled: true);
      }
      setState(() => _androidProcessId = null);
      return DownloadOutcome(success: false, error: _friendlyException(error));
    }
  }

  Future<dynamic> _handleAndroidMethodCall(MethodCall call) async {
    if (call.method == 'sharedContentReceived') {
      await _handleSharedContent(
        Map<dynamic, dynamic>.from(call.arguments as Map),
      );
      return null;
    }

    if (call.method != 'downloadProgress') {
      return null;
    }

    final arguments = Map<dynamic, dynamic>.from(call.arguments as Map);
    if (arguments['processId'] != _androidProcessId || _cancelRequested) {
      return null;
    }

    final line = arguments['line']?.toString() ?? '';
    final progress = arguments['progress'];
    _handleProcessLine(
      line,
      incomingProgress: progress is num ? progress : null,
    );

    return null;
  }

  void _handleProcessLine(String line, {num? incomingProgress}) {
    if (!mounted || line.trim().isEmpty || _cancelRequested) {
      return;
    }

    final trimmed = line.trim();
    if (trimmed.toLowerCase().startsWith('warning:')) {
      _rememberLog(trimmed);
      if (trimmed.toLowerCase().contains('could not update') ||
          trimmed.toLowerCase().contains('update failed')) {
        _setProgressState(
          stage: DownloadStage.updatingEngine,
          message: 'Download Engine is using the bundled version.',
          force: true,
        );
      }
      return;
    }

    final progressInfo = _parseProgress(trimmed);
    final inferredStage = _stageFromLine(trimmed, fallback: _stage);

    _rememberLog(trimmed);

    final hasProgress =
        incomingProgress != null || progressInfo.progress != null;
    final stage =
        hasProgress &&
            (inferredStage == DownloadStage.waiting ||
                inferredStage == DownloadStage.analyzing ||
                inferredStage == _stage)
        ? DownloadStage.downloading
        : inferredStage;

    _setProgressState(
      stage: stage,
      progress: incomingProgress == null
          ? progressInfo.progress
          : incomingProgress.clamp(0, 100).toDouble() / 100,
      speed: progressInfo.speed,
      eta: progressInfo.eta,
      message: _userFacingProcessMessage(trimmed, stage),
      force: inferredStage != _stage || trimmed.startsWith('ERROR:'),
    );
  }

  void _rememberLog(String line) {
    _recentLogLines.add(line);
    if (_recentLogLines.length > 12) {
      _recentLogLines.removeAt(0);
    }
  }

  String _userFacingProcessMessage(String line, DownloadStage stage) {
    final lower = line.toLowerCase();
    if (lower.startsWith('error:')) {
      return 'Download failed.';
    }
    if (lower.contains('unsupported url')) {
      return 'This URL is not supported.';
    }
    if (lower.contains('requested format') ||
        lower.contains('format is not available')) {
      return 'The selected quality is not available for this media.';
    }
    if (lower.contains('network') ||
        lower.contains('timed out') ||
        lower.contains('unable to download')) {
      return 'Network download failed.';
    }
    if (lower.contains('publishing') || lower.contains('mediastore')) {
      return 'Saving media file...';
    }
    if (lower.contains('retrying')) {
      return 'Trying the best available format...';
    }
    if (lower.contains('[extractaudio]')) {
      return 'Preparing audio file...';
    }
    if (lower.contains('[metadata]') || lower.contains('[embedthumbnail]')) {
      return 'Adding media details...';
    }
    if (lower.contains('[merger]') ||
        lower.contains('merging') ||
        lower.contains('ffmpeg') ||
        lower.contains('conversion')) {
      return 'Processing media...';
    }
    if (lower.contains('updating') || lower.contains('ready')) {
      return 'Preparing Download Engine...';
    }
    if (lower.contains('[download]') || stage == DownloadStage.downloading) {
      return 'Downloading media...';
    }
    return switch (stage) {
      DownloadStage.analyzing => 'Checking media link...',
      DownloadStage.updatingEngine => 'Preparing Download Engine...',
      DownloadStage.downloading => 'Downloading media...',
      DownloadStage.extracting => 'Preparing audio file...',
      DownloadStage.converting => 'Processing media...',
      DownloadStage.publishing => 'Saving media file...',
      DownloadStage.completed => 'Download completed.',
      DownloadStage.failed => 'Download failed.',
      DownloadStage.cancelled => 'Download cancelled.',
      DownloadStage.waiting => 'Ready to download.',
    };
  }

  void _setProgressState({
    required DownloadStage stage,
    double? progress,
    String? speed,
    String? eta,
    String? message,
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastProgressUiUpdate) <
            const Duration(milliseconds: 250)) {
      return;
    }
    _lastProgressUiUpdate = now;

    setState(() {
      _stage = stage;
      _progress = progress ?? _progress;
      _speed = speed ?? _speed;
      _eta = eta ?? _eta;
      if (message != null && message.isNotEmpty) {
        _message = message;
      }
      if (_activeQueueIndex >= 0 && _activeQueueIndex < _queueItems.length) {
        final item = _queueItems[_activeQueueIndex];
        item.progress = _progress;
        item.status = switch (stage) {
          DownloadStage.downloading => QueueItemStatus.downloading,
          DownloadStage.extracting ||
          DownloadStage.converting => QueueItemStatus.converting,
          DownloadStage.publishing => QueueItemStatus.publishing,
          DownloadStage.failed => QueueItemStatus.failed,
          DownloadStage.cancelled => QueueItemStatus.cancelled,
          _ => item.status,
        };
        final doneBefore = _queueItems
            .take(_activeQueueIndex)
            .where(
              (queued) =>
                  queued.status == QueueItemStatus.completed ||
                  queued.status == QueueItemStatus.failed ||
                  queued.status == QueueItemStatus.skipped ||
                  queued.status == QueueItemStatus.cancelled,
            )
            .length;
        _totalProgress = _queueItems.isEmpty
            ? null
            : ((doneBefore + (_progress ?? 0)).clamp(0, _queueItems.length)) /
                  _queueItems.length;
        unawaited(_saveQueueState());
      }
    });
  }

  Future<void> _addCompletedDownload({
    required String fileName,
    required String filePath,
    String? contentUri,
    bool isPlaylist = false,
    int? totalCount,
    int? completedCount,
    int? failedCount,
    int? skippedCount,
    String? folderPathOverride,
    DownloadMode downloadMode = DownloadMode.mp3,
    String? videoQualityLabel,
  }) async {
    final item = CompletedDownload(
      fileName: fileName,
      filePath: filePath,
      platform: _platformLabel(),
      completedAt: DateTime.now(),
      isPlaylist: isPlaylist,
      totalCount: totalCount,
      completedCount: completedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      folderPathOverride: folderPathOverride,
      contentUri: contentUri,
      downloadMode: downloadMode,
      videoQualityLabel: videoQualityLabel,
    );

    setState(() {
      _completedDownloads.insert(0, item);
      _progress = 1;
      _speed = null;
      _eta = null;
    });
    await _saveHistory();
  }

  Future<void> _removeHistoryEntry(CompletedDownload item) async {
    setState(() => _completedDownloads.remove(item));
    await _saveHistory();
  }

  Future<void> _clearDownloadHistory() async {
    setState(() => _completedDownloads.clear());
    await _saveHistory();
    _setStage(
      DownloadStage.waiting,
      'Download history cleared. Downloaded files were kept.',
    );
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyPreference,
      _completedDownloads
          .take(50)
          .map((item) => jsonEncode(item.toJson()))
          .toList(),
    );
  }

  Future<void> _saveQueueState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_queueItems.isEmpty) {
      await prefs.remove(_queueStatePreference);
      return;
    }
    await prefs.setString(
      _queueStatePreference,
      jsonEncode({
        'title': _queueTitle ?? 'Queue',
        'outputFolder': _queueOutputFolder ?? _outputFolder,
        'createdAt': (_queueCreatedAt ?? DateTime.now()).toIso8601String(),
        'activeIndex': _activeQueueIndex,
        'items': _queueItems.map((item) => item.toJson()).toList(),
      }),
    );
  }

  void _setStage(DownloadStage stage, String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = stage;
      _message = message;
      if (stage == DownloadStage.waiting ||
          stage == DownloadStage.failed ||
          stage == DownloadStage.cancelled) {
        _progress = null;
        _speed = null;
        _eta = null;
      }
    });
  }

  bool _looksLikeUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'''https?://[^\s<>"']+''').firstMatch(text);
    if (match == null) {
      return null;
    }
    var url = match.group(0)!.trim();
    while (url.isNotEmpty && RegExp(r'[.,;:)\]\}]$').hasMatch(url)) {
      url = url.substring(0, url.length - 1);
    }
    return _looksLikeUrl(url) ? url : null;
  }

  String? _facebookRedirectTarget(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if ((host == 'l.facebook.com' || host == 'lm.facebook.com') &&
        uri.path == '/l.php') {
      final target = uri.queryParameters['u'];
      if (target != null && _looksLikeUrl(target)) {
        return target;
      }
    }
    return null;
  }

  String _cleanTrackingUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return url;
    }

    final platform = _detectPlatform(url);
    final kept = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      final lowerKey = key.toLowerCase();
      if (_shouldKeepQueryParameter(platform, lowerKey)) {
        kept[key] = values;
      }
    });

    return uri.replace(queryParameters: kept.isEmpty ? null : kept).toString();
  }

  bool _shouldKeepQueryParameter(String platform, String key) {
    if (platform == 'YouTube') {
      return const {'v', 'list', 'index', 't', 'start'}.contains(key);
    }
    if (platform == 'Instagram') {
      return !key.startsWith('utm_') &&
          !const {'igsh', 'igshid', 'share_id'}.contains(key);
    }
    if (platform == 'Pinterest') {
      return !key.startsWith('utm_') &&
          !const {'invite_code', 'sender'}.contains(key);
    }
    if (platform == 'TikTok') {
      return !key.startsWith('utm_') &&
          !const {'is_from_webapp', 'sender_device', 'web_id'}.contains(key);
    }
    if (platform == 'X/Twitter') {
      return !key.startsWith('utm_') && !const {'s', 't'}.contains(key);
    }
    if (key.startsWith('utm_')) {
      return false;
    }
    return !const {
      'fbclid',
      'gclid',
      'gbraid',
      'wbraid',
      'msclkid',
      'mc_cid',
      'mc_eid',
      'igshid',
      'igsh',
      'si',
      'feature',
    }.contains(key);
  }

  String _detectPlatform(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == null || host.isEmpty) {
      return 'Unknown';
    }
    if (host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com') {
      return 'YouTube';
    }
    if (host == 'pinterest.com' ||
        host.endsWith('.pinterest.com') ||
        host == 'pin.it') {
      return 'Pinterest';
    }
    if (host == 'instagram.com' || host.endsWith('.instagram.com')) {
      return 'Instagram';
    }
    if (host == 'tiktok.com' ||
        host.endsWith('.tiktok.com') ||
        host == 'vm.tiktok.com') {
      return 'TikTok';
    }
    if (host == 'x.com' ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com')) {
      return 'X/Twitter';
    }
    if (host == 'l.facebook.com' || host == 'lm.facebook.com') {
      return 'Facebook redirect';
    }
    return host;
  }

  bool _looksLikeOptionalMetadataFailure() {
    final output = _recentLogLines.join('\n').toLowerCase();
    return output.contains('thumbnail') ||
        output.contains('metadata') ||
        output.contains('embedthumbnail') ||
        output.contains('atomicparsley');
  }

  String _readableFailureMessage(int exitCode) {
    final errors = _recentLogLines.where((line) {
      final lower = line.toLowerCase();
      if (lower.startsWith('warning:')) {
        return false;
      }
      return lower.startsWith('error:') ||
          lower.contains('unable to') ||
          lower.contains('failed') ||
          lower.contains('ffmpeg') ||
          lower.contains('not found') ||
          lower.contains('unsupported url') ||
          lower.contains('requested format') ||
          lower.contains('no video formats') ||
          lower.contains('http error') ||
          lower.contains('network');
    }).toList();

    if (errors.isNotEmpty) {
      return _friendlyYtDlpError(errors.last);
    }

    return exitCode == 0
        ? 'Download failed.'
        : 'Download failed. Check the URL and try again.';
  }

  String _friendlyYtDlpError(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('unsupported url')) {
      return 'This URL is not supported.';
    }
    if (lower.contains('requested format') ||
        lower.contains('no video formats') ||
        lower.contains('format is not available')) {
      return 'The requested video format is not available for this URL.';
    }
    if (lower.contains('http error 403') || lower.contains('forbidden')) {
      return 'The site blocked this download. Try again later or use a URL you are allowed to save.';
    }
    if (lower.contains('unable to download') ||
        lower.contains('network') ||
        lower.contains('timed out')) {
      return 'Network download failed. Check your connection and try again.';
    }
    if (lower.contains('ffmpeg')) {
      return 'Media Processing failed.';
    }
    if (line.startsWith('ERROR:')) {
      return 'Download failed.';
    }
    return 'Download failed.';
  }

  String _friendlyAndroidError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('mediastore') ||
        lower.contains('downloads') ||
        lower.contains('storage') ||
        lower.contains('permission')) {
      return 'Could not save the media file to Downloads.';
    }
    return _friendlyYtDlpError(message);
  }

  String? _friendlyWarning(String? message) {
    if (message == null || message.trim().isEmpty) {
      return null;
    }
    final lower = message.toLowerCase();
    if (lower.contains('ffmpeg') || lower.contains('merge')) {
      return 'Video saved using the best available format.';
    }
    if (lower.contains('metadata') || lower.contains('thumbnail')) {
      return 'Media saved. Some optional details could not be added.';
    }
    if (lower.contains('publish') || lower.contains('downloads')) {
      return 'Media saved, but the app could not publish it to Downloads.';
    }
    return message
        .replaceAll(RegExp('yt-dlp', caseSensitive: false), 'Download Engine')
        .replaceAll(RegExp('ffmpeg', caseSensitive: false), 'Media Processing');
  }

  String _friendlyException(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('yt-dlp was not found') ||
        lower.contains('yt-dlp') ||
        lower.contains('no such file') ||
        lower.contains('cannot find')) {
      return 'Engine is not working.';
    }
    if (lower.contains('ffmpeg')) {
      return 'Media Processing is not working.';
    }
    if (lower.contains('permission')) {
      return 'Folder is not writable.';
    }
    if (lower.contains('unsupported')) {
      return 'This URL is not supported.';
    }
    if (lower.contains('network') || lower.contains('timed out')) {
      return 'Network download failed.';
    }
    if (lower.contains('complete url') || lower.contains('paste a url')) {
      return text
          .replaceFirst('Exception: ', '')
          .replaceFirst('Bad state: ', '');
    }
    return 'Download failed.';
  }

  Future<ToolPaths> _resolveTools() async {
    final ytDlpNames = Platform.isWindows ? ['yt-dlp.exe'] : ['yt-dlp'];
    final ffmpegNames = Platform.isWindows ? ['ffmpeg.exe'] : ['ffmpeg'];

    final ytDlp = await _findTool(ytDlpNames);
    if (ytDlp == null) {
      throw StateError(
        'yt-dlp was not found. Install yt-dlp or bundle it with the app.',
      );
    }

    final ffmpeg = await _findTool(ffmpegNames);
    if (ffmpeg == null) {
      throw StateError(
        'FFmpeg was not found. Install FFmpeg or bundle it with the app.',
      );
    }

    return ToolPaths(
      ytDlp: ytDlp.path,
      ffmpeg: ffmpeg.path,
      ffmpegIsBundled: ffmpeg.isBundled,
      ytDlpVersion: await _readToolVersion(ytDlp.path),
      ffmpegVersion: await _readToolVersion(ffmpeg.path),
    );
  }

  Future<_ToolMatch?> _findTool(List<String> names) async {
    final bundledCandidates = _bundledSearchRoots()
        .expand((root) => names.map((name) => File(_joinPath(root, name))))
        .toList();

    for (final candidate in bundledCandidates) {
      if (await candidate.exists()) {
        return _ToolMatch(candidate.path, isBundled: true);
      }
    }

    for (final name in names) {
      final systemPath = await _resolveSystemCommandPath(name);
      if (systemPath != null && await _commandWorks(systemPath)) {
        return _ToolMatch(systemPath, isBundled: false);
      }
    }

    return null;
  }

  List<String> _bundledSearchRoots() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    final platformFolder = Platform.isWindows
        ? 'windows'
        : Platform.isAndroid
        ? 'android'
        : Platform.isLinux
        ? 'linux'
        : '';

    return <String>{
      _joinPath(executableDir, 'bin'),
      _joinPath(currentDir, 'bin'),
      if (platformFolder.isNotEmpty)
        _joinPath(_joinPath(executableDir, 'bin'), platformFolder),
      if (platformFolder.isNotEmpty)
        _joinPath(_joinPath(currentDir, 'bin'), platformFolder),
    }.toList();
  }

  Future<String?> _resolveSystemCommandPath(String command) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        command,
      ], runInShell: true).timeout(const Duration(seconds: 5));

      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return null;
      }

      return output.split(RegExp(r'\r?\n')).first.trim();
    } on Object {
      return null;
    }
  }

  Future<bool> _commandWorks(String command) async {
    try {
      final result = await Process.run(command, [
        '--version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<String> _readToolVersion(String command) async {
    try {
      final result = await Process.run(command, [
        '--version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (output.isEmpty) {
        return 'Unknown';
      }
      return output.split(RegExp(r'\r?\n')).first.trim();
    } on Object {
      return 'Unknown';
    }
  }

  Future<File?> _findNewestMedia(
    String folder,
    DateTime startedAt,
    DownloadMode downloadMode, {
    String? taskId,
  }) async {
    final directory = Directory(folder);
    if (!await directory.exists()) {
      return null;
    }
    final extensions = downloadMode == DownloadMode.mp3
        ? const {'mp3'}
        : const {'mp4', 'mkv', 'webm', 'mov', 'm4v'};

    File? newest;
    DateTime? newestModified;

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final extension = _extension(entity.path).toLowerCase();
      if (!extensions.contains(extension)) {
        continue;
      }
      if (_isTemporaryDownloadPath(entity.path)) {
        continue;
      }
      if (taskId != null && !_fileName(entity.path).contains(taskId)) {
        continue;
      }

      final modified = await entity.lastModified();
      if (modified.isBefore(startedAt.subtract(const Duration(seconds: 2)))) {
        continue;
      }

      if (newestModified == null || modified.isAfter(newestModified)) {
        newest = entity;
        newestModified = modified;
      }
    }

    return newest;
  }

  bool _isTemporaryDownloadPath(String path) {
    final name = _fileName(path).toLowerCase();
    final extension = _extension(path).toLowerCase();
    return const {'part', 'ytdl', 'tmp', 'temp', 'aria2'}.contains(extension) ||
        name.endsWith('.part') ||
        name.contains('.part-') ||
        name.endsWith('.ytdl') ||
        name.endsWith('.tmp') ||
        name.endsWith('.temp');
  }

  Future<String> _resolveDefaultDownloadFolder() async {
    if (Platform.isAndroid) {
      try {
        final folder = await _androidDownloaderChannel.invokeMethod<String>(
          'getDefaultDownloadFolder',
        );
        if (folder != null && folder.isNotEmpty) {
          return folder;
        }
      } on Object {
        return '/storage/emulated/0/Download/DownAnyMedia';
      }
    }

    final base = _defaultDownloadsBase();
    return _joinPath(base, 'DownAnyMedia');
  }

  String _defaultDownloadsBase() {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return _joinPath(userProfile, 'Downloads');
      }
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return _joinPath(home, 'Downloads');
      }
    }

    return Directory.systemTemp.path;
  }

  _ProgressInfo _parseProgress(String line) {
    final percent = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
    final speed = RegExp(r'\bat\s+([^\s]+/s)').firstMatch(line);
    final eta = RegExp(r'\bETA\s+([^\s]+)').firstMatch(line);
    final parsedProgress = percent == null
        ? null
        : double.tryParse(percent.group(1)!);
    return _ProgressInfo(
      progress: parsedProgress == null
          ? null
          : parsedProgress.clamp(0, 100).toDouble() / 100,
      speed: speed?.group(1),
      eta: eta?.group(1),
    );
  }

  DownloadStage _stageFromLine(String line, {required DownloadStage fallback}) {
    final lower = line.toLowerCase();
    if (lower.contains('updating yt-dlp') ||
        lower.contains('yt-dlp is ready')) {
      return DownloadStage.updatingEngine;
    }
    if (lower.contains('[extractaudio]')) {
      return DownloadStage.extracting;
    }
    if (lower.contains('[metadata]') ||
        lower.contains('[embedthumbnail]') ||
        lower.contains('[thumbnailsconvertor]') ||
        lower.contains('[merger]') ||
        lower.contains('merging formats') ||
        lower.contains('merging video') ||
        lower.contains('destination:')) {
      return DownloadStage.converting;
    }
    if (lower.contains('publishing') || lower.contains('mediastore')) {
      return DownloadStage.publishing;
    }
    if (line.startsWith('ERROR:')) {
      return DownloadStage.failed;
    }
    if (lower.contains('[download]')) {
      return DownloadStage.downloading;
    }
    return fallback == DownloadStage.waiting
        ? DownloadStage.analyzing
        : fallback;
  }

  String _joinPath(String first, String second) {
    if (first.isEmpty) {
      return second;
    }
    final separator = Platform.pathSeparator;
    if (first.endsWith('/') || first.endsWith(r'\')) {
      return '$first$second';
    }
    return '$first$separator$second';
  }

  String _parentFolderForQueue(String playlistFolder, String folderName) {
    final normalized = playlistFolder.replaceAll(r'\', '/');
    if (normalized.endsWith('/$folderName')) {
      return playlistFolder.substring(
        0,
        playlistFolder.length - folderName.length - 1,
      );
    }
    return _outputFolder ?? playlistFolder;
  }

  String? _androidRelativeDownloadFolder(String? folder) {
    if (folder == null || folder.trim().isEmpty) {
      return null;
    }
    final normalized = folder
        .trim()
        .replaceAll(r'\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    const primaryPrefix = '/storage/emulated/0/';
    if (!normalized.startsWith(primaryPrefix)) {
      return null;
    }
    final relative = normalized.substring(primaryPrefix.length).trim();
    if (relative == 'Download' || relative.startsWith('Download/')) {
      return relative;
    }
    if (relative == 'Downloads' || relative.startsWith('Downloads/')) {
      return 'Download${relative.substring('Downloads'.length)}';
    }
    return null;
  }

  String _simplePath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return 'Downloads/DownAnyMedia';
    }
    final normalized = path.trim().replaceAll(r'\', '/');
    final androidRelative = _androidRelativeDownloadFolder(normalized);
    if (androidRelative != null) {
      return androidRelative.replaceFirst('Download', 'Downloads');
    }

    final home = Platform.environment['HOME']?.replaceAll(r'\', '/');
    if (home != null && normalized.startsWith('$home/')) {
      return normalized.substring(home.length + 1);
    }

    final userProfile = Platform.environment['USERPROFILE']?.replaceAll(
      r'\',
      '/',
    );
    if (userProfile != null && normalized.startsWith('$userProfile/')) {
      return normalized.substring(userProfile.length + 1);
    }

    final downloadsIndex = normalized.toLowerCase().lastIndexOf('/downloads/');
    if (downloadsIndex >= 0) {
      return normalized.substring(downloadsIndex + 1);
    }

    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('/');
    }
    return normalized;
  }

  String _sanitizeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return 'download';
    }
    return cleaned.length > 120 ? cleaned.substring(0, 120).trim() : cleaned;
  }

  Future<String> _uniqueDesktopBaseName(String folder, String baseName) async {
    await Directory(folder).create(recursive: true);
    var candidate = baseName;
    var count = 1;
    while (await File(_joinPath(folder, '$candidate.mp3')).exists() ||
        await File(_joinPath(folder, '$candidate.mp4')).exists()) {
      candidate = '$baseName ($count)';
      count += 1;
    }
    return candidate;
  }

  String _extension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _playlistFallbackName() {
    final now = DateTime.now();
    String two(int number) => number.toString().padLeft(2, '0');
    return 'Playlist-${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}-${two(now.minute)}';
  }

  String? _currentQueueLabel() {
    if (_activeQueueIndex < 0 || _activeQueueIndex >= _queueItems.length) {
      return null;
    }
    final item = _queueItems[_activeQueueIndex];
    return 'Current: ${_activeQueueIndex + 1}/${_queueItems.length} • ${item.title}';
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SettingsPage(
          folder: _outputFolder ?? 'Loading...',
          displayFolder: _simplePath(_outputFolder),
          canChooseFolder: !_isRunning,
          playlistFilenameStyle: _playlistFilenameStyle,
          embedMetadata: _embedMetadata,
          embedThumbnail: _embedThumbnail,
          audioQualityPreset: _audioQualityPreset,
          downloadMode: _downloadMode,
          themeMode: widget.themeMode,
          smartUrlCleaning: _smartUrlCleaning,
          onOpenFolder: _openCurrentDownloadFolder,
          onChooseFolder: _chooseDownloadFolder,
          onPlaylistFilenameStyleChanged: _setPlaylistFilenameStyle,
          onEmbedMetadataChanged: _setEmbedMetadata,
          onEmbedThumbnailChanged: _setEmbedThumbnail,
          onAudioQualityPresetChanged: _setAudioQualityPreset,
          onThemeModeChanged: widget.onThemeModeChanged,
          onSmartUrlCleaningChanged: _setSmartUrlCleaning,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputText = _urlController.text.trim();
    final inputUrl = _extractFirstUrl(inputText) ?? inputText;
    final engineReady =
        _engineInfo.ytDlpAvailable &&
        (_engineInfo.ffmpegAvailable ||
            (Platform.isAndroid && _downloadMode == DownloadMode.video));
    final canDownload =
        !_isRunning &&
        inputText.isNotEmpty &&
        _looksLikeUrl(inputUrl) &&
        engineReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DownAnyMedia'),
        actions: [
          if (_adsSupported)
            IconButton(
              tooltip: _adsHidden
                  ? 'Ads hidden'
                  : _rewardedAdLoading
                  ? 'Loading'
                  : 'Hide ads',
              onPressed: _adsHidden || _rewardedAdLoading
                  ? null
                  : _showRewardedAdForAdRemoval,
              icon: Icon(
                _adsHidden
                    ? Icons.visibility_off_outlined
                    : Icons.video_collection_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _isRunning ? null : _openSettingsPage,
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'about') {
                _showAboutDialog();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: EdgeInsets.all(isWide ? 32 : 16),
                  children: [
                    TextField(
                      key: const ValueKey('urlInput'),
                      controller: _urlController,
                      enabled: !_isRunning,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Media URL',
                        hintText: 'Paste a media URL to get started',
                        prefixIcon: const Icon(Icons.link),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_urlController.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear URL',
                                onPressed: _isRunning
                                    ? null
                                    : () {
                                        _urlController.clear();
                                        _analysisTimer?.cancel();
                                        setState(() {
                                          _playlistInfo = null;
                                          _lastAnalyzedUrl = null;
                                        });
                                      },
                                icon: const Icon(Icons.clear),
                              ),
                            IconButton(
                              key: const ValueKey('pasteButton'),
                              tooltip: 'Paste from clipboard',
                              onPressed: _isRunning
                                  ? null
                                  : _pasteFromClipboard,
                              icon: const Icon(Icons.content_paste),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      onChanged: _onUrlChanged,
                      onSubmitted: (_) {
                        if (canDownload) {
                          _startDownload();
                        }
                      },
                    ),
                    if (_incomingUrlMessage != null) ...[
                      const SizedBox(height: 12),
                      _IncomingUrlBanner(
                        message: _isRunning
                            ? 'URL received from another app. It is in the input field for later.'
                            : _incomingUrlMessage!,
                        onDismiss: () =>
                            setState(() => _incomingUrlMessage = null),
                      ),
                    ],
                    if (_playlistInfo != null) ...[
                      const SizedBox(height: 12),
                      _PlaylistPanel(
                        info: _playlistInfo!,
                        downloadMode: _downloadMode,
                        onDownload:
                            canDownload &&
                                _playlistInfo!.status ==
                                    UrlAnalysisStatus.playlist
                            ? _startDownload
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _DownloadModePanel(
                      downloadMode: _downloadMode,
                      videoQuality: _videoQualityPreset,
                      enabled: !_isRunning,
                      onDownloadModeChanged: _setDownloadMode,
                      onVideoQualityChanged: _setVideoQualityPreset,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('downloadButton'),
                            onPressed: canDownload ? _startDownload : null,
                            icon: Icon(
                              _downloadMode == DownloadMode.mp3
                                  ? Icons.music_note
                                  : Icons.movie_outlined,
                            ),
                            label: Text(
                              _downloadMode == DownloadMode.mp3
                                  ? 'Download Audio'
                                  : 'Download Video',
                            ),
                          ),
                        ),
                        if (_isRunning) ...[
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('cancelButton'),
                            onPressed: _cancelDownload,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    _StatusPanel(
                      stage: _stage,
                      progress: _progress,
                      totalProgress: _totalProgress,
                      currentItemLabel: _currentQueueLabel(),
                      speed: _speed,
                      eta: _eta,
                      message: _message,
                      outputFolder: _outputFolder,
                      displayOutputFolder: _simplePath(_outputFolder),
                      debugLines: null,
                    ),
                    if (_queueItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _QueuePanel(
                        title: _queueTitle ?? 'Queue',
                        items: _queueItems,
                        activeIndex: _activeQueueIndex,
                        isRunning: _isRunning,
                        isPaused: _queuePaused,
                        onPause: _pauseQueue,
                        onResume: _resumeQueue,
                        onCancelCurrent: _cancelDownload,
                        onCancelAll: _cancelAllQueue,
                        onRetryFailed: _retryFailedQueue,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Engine & download settings',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _engineInfo.canDownload
                              ? 'Engine ready'
                              : 'Engine not ready',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _engineInfo.canDownload
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                        ),
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          _EngineStatusPanel(
                            info: _engineInfo,
                            onRefresh: _isRunning
                                ? null
                                : _refreshEngineStatus,
                          ),
                          const SizedBox(height: 12),
                          _FolderPanel(
                            folder: _simplePath(_outputFolder),
                            canChoose: !_isRunning,
                            onChoose: _chooseDownloadFolder,
                            onOpen: _outputFolder == null
                                ? null
                                : _openCurrentDownloadFolder,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Download History',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_completedDownloads.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear history',
                            onPressed: _clearDownloadHistory,
                            icon: const Icon(Icons.clear_all),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_completedDownloads.isEmpty)
                      Text(
                        'Downloaded files will appear here.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ..._completedDownloads.map(
                        (item) => _CompletedDownloadTile(
                          item: item,
                          completedLabel: _formatDateTime(item.completedAt),
                          pathLabel: _simplePath(
                            item.isPlaylist ? item.folderPath : item.filePath,
                          ),
                          onTap: item.isPlaylist
                              ? () => _openFolder(item)
                              : () => _openFile(item),
                          onOpenFolder: () => _openFolder(item),
                          onDeleteHistory: () => _removeHistoryEntry(item),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBannerAdBar(),
    );
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About DownAnyMedia'),
        content: const SingleChildScrollView(
          child: Text(
            'You can download audio or video only if you own it, have '
            'permission to download it, or are legally allowed to save it.\n\n'
            'Supports audio and video downloads from supported social, '
            'entertainment, and media platforms.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ToolMatch {
  const _ToolMatch(this.path, {required this.isBundled});

  final String path;
  final bool isBundled;
}

class _ProgressInfo {
  const _ProgressInfo({this.progress, this.speed, this.eta});

  final double? progress;
  final String? speed;
  final String? eta;
}

class _EngineStatusPanel extends StatelessWidget {
  const _EngineStatusPanel({required this.info, required this.onRefresh});

  final EngineInfo info;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final working = info.canDownload;
    final statusColor = working
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 14, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Engine Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Engine Status',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              working ? 'Working' : 'Not Working',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderPanel extends StatelessWidget {
  const _FolderPanel({
    required this.folder,
    required this.canChoose,
    required this.onChoose,
    required this.onOpen,
  });

  final String folder;
  final bool canChoose;
  final VoidCallback onChoose;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download folder',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(folder),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open folder'),
                ),
                if (canChoose)
                  OutlinedButton.icon(
                    onPressed: onChoose,
                    icon: const Icon(Icons.drive_folder_upload),
                    label: const Text('Choose folder'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingUrlBanner extends StatelessWidget {
  const _IncomingUrlBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.ios_share, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}

class _DownloadModePanel extends StatelessWidget {
  const _DownloadModePanel({
    required this.downloadMode,
    required this.videoQuality,
    required this.enabled,
    required this.onDownloadModeChanged,
    required this.onVideoQualityChanged,
  });

  final DownloadMode downloadMode;
  final VideoQualityPreset videoQuality;
  final bool enabled;
  final ValueChanged<DownloadMode> onDownloadModeChanged;
  final ValueChanged<VideoQualityPreset> onVideoQualityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download mode',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<DownloadMode>(
              segments: const [
                ButtonSegment(
                  value: DownloadMode.mp3,
                  icon: Icon(Icons.music_note),
                  label: Text('Audio'),
                ),
                ButtonSegment(
                  value: DownloadMode.video,
                  icon: Icon(Icons.movie_outlined),
                  label: Text('Video'),
                ),
              ],
              selected: {downloadMode},
              onSelectionChanged: enabled
                  ? (values) => onDownloadModeChanged(values.first)
                  : null,
            ),
            if (downloadMode == DownloadMode.video) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<VideoQualityPreset>(
                initialValue: videoQuality,
                decoration: const InputDecoration(
                  labelText: 'Video quality',
                  prefixIcon: Icon(Icons.high_quality),
                ),
                items: VideoQualityPreset.values
                    .map(
                      (quality) => DropdownMenuItem(
                        value: quality,
                        child: Text(quality.label),
                      ),
                    )
                    .toList(),
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          onVideoQualityChanged(value);
                        }
                      }
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.folder,
    required this.displayFolder,
    required this.canChooseFolder,
    required this.playlistFilenameStyle,
    required this.embedMetadata,
    required this.embedThumbnail,
    required this.audioQualityPreset,
    required this.downloadMode,
    required this.themeMode,
    required this.smartUrlCleaning,
    required this.onOpenFolder,
    required this.onChooseFolder,
    required this.onPlaylistFilenameStyleChanged,
    required this.onEmbedMetadataChanged,
    required this.onEmbedThumbnailChanged,
    required this.onAudioQualityPresetChanged,
    required this.onThemeModeChanged,
    required this.onSmartUrlCleaningChanged,
  });

  final String folder;
  final String displayFolder;
  final bool canChooseFolder;
  final PlaylistFilenameStyle playlistFilenameStyle;
  final bool embedMetadata;
  final bool embedThumbnail;
  final AudioQualityPreset audioQualityPreset;
  final DownloadMode downloadMode;
  final AppThemeMode themeMode;
  final bool smartUrlCleaning;
  final Future<void> Function() onOpenFolder;
  final Future<String?> Function() onChooseFolder;
  final Future<void> Function(PlaylistFilenameStyle value)
  onPlaylistFilenameStyleChanged;
  final Future<void> Function(bool value) onEmbedMetadataChanged;
  final Future<void> Function(bool value) onEmbedThumbnailChanged;
  final Future<void> Function(AudioQualityPreset value)
  onAudioQualityPresetChanged;
  final Future<void> Function(AppThemeMode value) onThemeModeChanged;
  final Future<void> Function(bool value) onSmartUrlCleaningChanged;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late PlaylistFilenameStyle _playlistFilenameStyle;
  late bool _embedMetadata;
  late bool _embedThumbnail;
  late AppThemeMode _themeMode;
  late bool _smartUrlCleaning;
  late AudioQualityPreset _audioQualityPreset;
  late String _displayFolder;

  @override
  void initState() {
    super.initState();
    _playlistFilenameStyle = widget.playlistFilenameStyle;
    _embedMetadata = widget.embedMetadata;
    _embedThumbnail = widget.embedThumbnail;
    _themeMode = widget.themeMode;
    _smartUrlCleaning = widget.smartUrlCleaning;
    _audioQualityPreset = widget.audioQualityPreset;
    _displayFolder = widget.displayFolder;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Current download folder',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_displayFolder),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onOpenFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open folder'),
                ),
                if (widget.canChooseFolder)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final folder = await widget.onChooseFolder();
                      if (folder != null && mounted) {
                        setState(() {
                          _displayFolder = _simpleSettingsPath(folder);
                        });
                      }
                    },
                    icon: const Icon(Icons.drive_folder_upload),
                    label: const Text('Choose folder'),
                  ),
              ],
            ),
            const Divider(height: 32),
            DropdownButtonFormField<AppThemeMode>(
              initialValue: _themeMode,
              decoration: const InputDecoration(
                labelText: 'Dark Mode',
                prefixIcon: Icon(Icons.dark_mode_outlined),
              ),
              items: AppThemeMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _themeMode = value);
                  widget.onThemeModeChanged(value);
                }
              },
            ),
            const Divider(height: 32),
            DropdownButtonFormField<PlaylistFilenameStyle>(
              initialValue: _playlistFilenameStyle,
              decoration: const InputDecoration(
                labelText: 'Playlist filename style',
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
              items: PlaylistFilenameStyle.values
                  .map(
                    (style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _playlistFilenameStyle = value);
                  widget.onPlaylistFilenameStyleChanged(value);
                }
              },
            ),
            const SizedBox(height: 16),
            if (widget.downloadMode == DownloadMode.mp3) ...[
              DropdownButtonFormField<AudioQualityPreset>(
                initialValue: _audioQualityPreset,
                decoration: const InputDecoration(
                  labelText: 'Audio quality',
                  prefixIcon: Icon(Icons.equalizer),
                ),
                items: AudioQualityPreset.values
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _audioQualityPreset = value);
                    widget.onAudioQualityPresetChanged(value);
                  }
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Embed metadata'),
                secondary: const Icon(Icons.badge_outlined),
                value: _embedMetadata,
                onChanged: (value) {
                  setState(() => _embedMetadata = value);
                  widget.onEmbedMetadataChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Embed thumbnail'),
                secondary: const Icon(Icons.image_outlined),
                value: _embedThumbnail,
                onChanged: (value) {
                  setState(() => _embedThumbnail = value);
                  widget.onEmbedThumbnailChanged(value);
                },
              ),
            ] else
              Text(
                'Metadata, thumbnail, and audio-quality settings are used only in Audio mode.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart URL cleaning'),
              subtitle: const Text(
                'Removes tracking parameters for better anonymity. Warning: this can increase download time.',
              ),
              secondary: const Icon(Icons.cleaning_services_outlined),
              value: _smartUrlCleaning,
              onChanged: (value) {
                setState(() => _smartUrlCleaning = value);
                widget.onSmartUrlCleaningChanged(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _simpleSettingsPath(String path) {
  final normalized = path.trim().replaceAll(r'\', '/');
  const primaryPrefix = '/storage/emulated/0/';
  if (normalized.startsWith(primaryPrefix)) {
    final relative = normalized.substring(primaryPrefix.length);
    return relative.replaceFirst('Download', 'Downloads');
  }

  final home = Platform.environment['HOME']?.replaceAll(r'\', '/');
  if (home != null && normalized.startsWith('$home/')) {
    return normalized.substring(home.length + 1);
  }

  final userProfile = Platform.environment['USERPROFILE']?.replaceAll(
    r'\',
    '/',
  );
  if (userProfile != null && normalized.startsWith('$userProfile/')) {
    return normalized.substring(userProfile.length + 1);
  }

  return normalized;
}

class _PlaylistPanel extends StatelessWidget {
  const _PlaylistPanel({
    required this.info,
    required this.downloadMode,
    required this.onDownload,
  });

  final PlaylistInfo info;
  final DownloadMode downloadMode;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = info.items.take(5).toList();
    final statusText = switch (info.status) {
      UrlAnalysisStatus.analyzing => 'Analyzing URL...',
      UrlAnalysisStatus.single => 'Single media URL detected.',
      UrlAnalysisStatus.playlist => 'Playlist detected.',
      UrlAnalysisStatus.unsupported => info.error ?? 'Unsupported URL.',
      UrlAnalysisStatus.failed => info.error ?? 'Could not analyze URL.',
      UrlAnalysisStatus.idle => '',
    };

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.queue_music),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (info.isPlaylist) ...[
              const SizedBox(height: 8),
              Text(info.title ?? 'Playlist'),
              if (info.totalCount != null)
                Text('${info.totalCount} items detected'),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...preview.map(
                  (entry) => Text(
                    '${entry.index}. ${entry.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (info.items.length > preview.length)
                  Text('+ ${info.items.length - preview.length} more'),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(
                  downloadMode == DownloadMode.mp3
                      ? 'Download full playlist as Audio'
                      : 'Download full playlist as Video',
                ),
              ),
            ],
            if (info.status == UrlAnalysisStatus.unsupported &&
                info.error != null) ...[
              const SizedBox(height: 8),
              Text(
                info.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.title,
    required this.items,
    required this.activeIndex,
    required this.isRunning,
    required this.isPaused,
    required this.onPause,
    required this.onResume,
    required this.onCancelCurrent,
    required this.onCancelAll,
    required this.onRetryFailed,
  });

  final String title;
  final List<DownloadQueueItem> items;
  final int activeIndex;
  final bool isRunning;
  final bool isPaused;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancelCurrent;
  final VoidCallback onCancelAll;
  final VoidCallback onRetryFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = items
        .where((item) => item.status == QueueItemStatus.completed)
        .length;
    final failed = items
        .where((item) => item.status == QueueItemStatus.failed)
        .length;
    final skipped = items
        .where((item) => item.status == QueueItemStatus.skipped)
        .length;
    final finished = completed + failed + skipped;
    final activeItem = activeIndex >= 0 && activeIndex < items.length
        ? items[activeIndex]
        : null;
    final pending = items
        .where((item) => item.status == QueueItemStatus.waiting)
        .length;
    final hasFailed = failed > 0;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$finished/${items.length} finished • $completed completed • $failed failed • $skipped skipped',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: pending > 0 && !isRunning ? onResume : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(isPaused ? 'Resume queue' : 'Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: isRunning ? onPause : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause queue'),
                ),
                OutlinedButton.icon(
                  onPressed: isRunning ? onCancelCurrent : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Cancel current'),
                ),
                OutlinedButton.icon(
                  onPressed: items.isNotEmpty ? onCancelAll : null,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel all'),
                ),
                OutlinedButton.icon(
                  onPressed: hasFailed && !isRunning ? onRetryFailed : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry failed'),
                ),
              ],
            ),
            if (activeItem != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current item ${activeIndex + 1} of ${items.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeItem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    if (activeItem.progress != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: activeItem.progress),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            ...items.take(8).indexed.map((entry) {
              final index = entry.$1;
              final item = entry.$2;
              final isActive = index == activeIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _queueIcon(item.status),
                      size: 18,
                      color: isActive ? theme.colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.index}. ${item.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(item.status.label),
                  ],
                ),
              );
            }),
            if (items.length > 8) Text('+ ${items.length - 8} queued items'),
          ],
        ),
      ),
    );
  }

  IconData _queueIcon(QueueItemStatus status) {
    return switch (status) {
      QueueItemStatus.waiting => Icons.schedule,
      QueueItemStatus.analyzing => Icons.manage_search,
      QueueItemStatus.downloading => Icons.downloading,
      QueueItemStatus.converting => Icons.sync,
      QueueItemStatus.publishing => Icons.publish,
      QueueItemStatus.completed => Icons.check_circle_outline,
      QueueItemStatus.failed => Icons.error_outline,
      QueueItemStatus.skipped => Icons.skip_next,
      QueueItemStatus.cancelled => Icons.cancel_outlined,
    };
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.stage,
    required this.progress,
    required this.totalProgress,
    required this.currentItemLabel,
    required this.speed,
    required this.eta,
    required this.message,
    required this.outputFolder,
    required this.displayOutputFolder,
    required this.debugLines,
  });

  final DownloadStage stage;
  final double? progress;
  final double? totalProgress;
  final String? currentItemLabel;
  final String? speed;
  final String? eta;
  final String? message;
  final String? outputFolder;
  final String displayOutputFolder;
  final List<String>? debugLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = switch (stage) {
      DownloadStage.analyzing ||
      DownloadStage.updatingEngine ||
      DownloadStage.downloading ||
      DownloadStage.extracting ||
      DownloadStage.converting ||
      DownloadStage.publishing => true,
      _ => false,
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_stageIcon(stage), color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stage.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isActive && progress != null)
                  Text(
                    '${(progress! * 100).clamp(0, 100).toStringAsFixed(1)}%',
                  ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
            if (isActive && totalProgress != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: totalProgress),
                  ),
                  const SizedBox(width: 10),
                  Text('${(totalProgress! * 100).toStringAsFixed(0)}% total'),
                ],
              ),
            ],
            if (currentItemLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                currentItemLabel!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (speed != null || eta != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (speed != null) Text('Speed $speed'),
                  if (eta != null) Text('ETA $eta'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(message ?? 'Ready to download.'),
            if (outputFolder != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saving to $displayOutputFolder',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (debugLines != null && debugLines!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Details'),
                children: [
                  for (final line in debugLines!)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        line,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _stageIcon(DownloadStage stage) {
    return switch (stage) {
      DownloadStage.waiting => Icons.hourglass_empty,
      DownloadStage.analyzing => Icons.manage_search,
      DownloadStage.updatingEngine => Icons.system_update,
      DownloadStage.downloading => Icons.downloading,
      DownloadStage.extracting => Icons.graphic_eq,
      DownloadStage.converting => Icons.sync,
      DownloadStage.publishing => Icons.publish,
      DownloadStage.completed => Icons.check_circle_outline,
      DownloadStage.failed => Icons.error_outline,
      DownloadStage.cancelled => Icons.cancel_outlined,
    };
  }
}

class _CompletedDownloadTile extends StatelessWidget {
  const _CompletedDownloadTile({
    required this.item,
    required this.completedLabel,
    required this.pathLabel,
    required this.onTap,
    required this.onOpenFolder,
    required this.onDeleteHistory,
  });

  final CompletedDownload item;
  final String completedLabel;
  final String pathLabel;
  final VoidCallback onTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onDeleteHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open folder',
                    onPressed: onOpenFolder,
                    icon: const Icon(Icons.folder_open),
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  IconButton(
                    tooltip: 'Delete from history',
                    onPressed: onDeleteHistory,
                    icon: const Icon(Icons.delete_outline),
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.isPlaylist
                    ? '${item.downloadMode.historyLabel} playlist • ${item.platform} • $completedLabel'
                    : '${item.downloadMode.historyLabel} • ${item.platform} • $completedLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (item.downloadMode == DownloadMode.video &&
                  item.videoQualityLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Quality: ${item.videoQualityLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (item.isPlaylist) ...[
                const SizedBox(height: 6),
                Text(
                  '${item.totalCount ?? ((item.completedCount ?? 0) + (item.failedCount ?? 0) + (item.skippedCount ?? 0))} total • ${item.completedCount ?? 0} completed • ${item.failedCount ?? 0} failed • ${item.skippedCount ?? 0} skipped',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              SelectableText(
                item.isPlaylist ? 'Folder: $pathLabel' : pathLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _platformLabel() {
  if (Platform.isAndroid) {
    return 'Android';
  }
  if (Platform.isWindows) {
    return 'Windows';
  }
  if (Platform.isLinux) {
    return 'Linux';
  }
  return Platform.operatingSystem;
}
