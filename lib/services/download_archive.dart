import 'dart:io';

import '../models/playlist_selection.dart';

/// yt-dlp `--download-archive` support (Feature 1d) so re-running a playlist
/// never re-downloads what's already saved.
///
/// Archive line format is yt-dlp's native `<extractor> <video_id>`, one per
/// line. One archive file per destination folder. Desktop passes the path to
/// yt-dlp directly; Android keeps it in app-private storage (MainActivity
/// injects it into the request), and the Dart side reads it for UI badges.
class DownloadArchive {
  const DownloadArchive._();

  static const fileName = '.downanymedia_archive.txt';

  static String pathFor(String folder) {
    final sep = Platform.pathSeparator;
    final trimmed = folder.endsWith(sep)
        ? folder.substring(0, folder.length - 1)
        : folder;
    return '$trimmed$sep$fileName';
  }

  /// Read the set of archived video ids (the second whitespace token per
  /// line). Missing/unreadable file ⇒ empty set (never throws to the caller).
  static Future<Set<String>> readIds(String archivePath) async {
    final file = File(archivePath);
    if (!await file.exists()) return <String>{};
    try {
      final ids = <String>{};
      for (final line in await file.readAsLines()) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1].isNotEmpty) {
          ids.add(parts[1]);
        } else if (parts.length == 1 && parts[0].isNotEmpty) {
          ids.add(parts[0]); // tolerate id-only lines
        }
      }
      return ids;
    } on IOException {
      return <String>{};
    }
  }

  /// Append one `extractor id` line if not already present.
  static Future<void> append(
    String archivePath,
    String extractor,
    String id,
  ) async {
    if (id.isEmpty) return;
    final existing = await readIds(archivePath);
    if (existing.contains(id)) return;
    final file = File(archivePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '$extractor $id\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Mark playlist entries already in the archive as downloaded and, when
  /// [skipDownloaded] is on, auto-deselect them (the user can re-select to
  /// force a re-download).
  static void crossReference(
    List<SelectablePlaylistEntry> entries,
    Set<String> archivedIds, {
    required bool skipDownloaded,
  }) {
    if (archivedIds.isEmpty) return;
    for (final entry in entries) {
      if (entry.id.isNotEmpty && archivedIds.contains(entry.id)) {
        entry.isDownloaded = true;
        if (skipDownloaded) entry.isSelected = false;
      }
    }
  }
}
