import 'package:flutter/foundation.dart';

/// Rotating in-app diagnostics log (Feature 3d).
///
/// Capped at 500 entries / 256 KB so a long session can't grow unbounded.
/// Every mapped [AppError] and every silent fallback (remote config, etc.)
/// lands here — this is what makes remote debugging of user reports possible.
/// Viewable from Settings → Diagnostics, shareable as plain text.
enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  @override
  String toString() =>
      '${time.toIso8601String()} [${level.name.toUpperCase()}] $message';
}

class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const int maxEntries = 500;
  static const int maxBytes = 256 * 1024;

  final List<LogEntry> _entries = [];
  int _bytes = 0;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(LogLevel level, String message) {
    final entry = LogEntry(DateTime.now(), level, message);
    _entries.add(entry);
    _bytes += entry.toString().length + 1;
    // Trim oldest-first until back under both caps.
    while (_entries.length > maxEntries || _bytes > maxBytes) {
      if (_entries.isEmpty) {
        _bytes = 0;
        break;
      }
      final removed = _entries.removeAt(0);
      _bytes -= removed.toString().length + 1;
    }
    notifyListeners();
  }

  void debug(String message) => log(LogLevel.debug, message);
  void info(String message) => log(LogLevel.info, message);
  void warning(String message) => log(LogLevel.warning, message);
  void error(String message) => log(LogLevel.error, message);

  /// Full log as shareable text, newest last.
  String export() => _entries.map((e) => e.toString()).join('\n');

  void clear() {
    _entries.clear();
    _bytes = 0;
    notifyListeners();
  }
}
