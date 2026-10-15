import 'package:flutter/foundation.dart';

import '../app_strings.dart';

/// Availability reported by yt-dlp's flat extraction (Feature 1a). Unavailable
/// entries are greyed out and non-selectable in the UI.
enum EntryAvailability {
  available,
  private,
  deleted,
  unavailable;

  bool get isPlayable => this == EntryAvailability.available;

  String? get badge => switch (this) {
    available => null,
    private => AppStrings.badgePrivate,
    deleted => AppStrings.badgeDeleted,
    unavailable => AppStrings.badgeUnavailable,
  };

  /// Map a yt-dlp `availability` field and/or a placeholder title to a state.
  static EntryAvailability from({String? availability, String? title}) {
    final a = availability?.toLowerCase() ?? '';
    final t = title?.toLowerCase() ?? '';
    if (a.contains('private') || t.contains('[private')) {
      return EntryAvailability.private;
    }
    if (t.contains('[deleted')) return EntryAvailability.deleted;
    if (a.contains('unavailable') ||
        a == 'needs_auth' ||
        a == 'premium_only' ||
        a == 'subscriber_only' ||
        t.contains('[unavailable')) {
      return EntryAvailability.unavailable;
    }
    return EntryAvailability.available;
  }
}

class SelectablePlaylistEntry {
  SelectablePlaylistEntry({
    required this.index,
    required this.id,
    required this.title,
    required this.url,
    this.duration,
    this.uploader,
    this.availability = EntryAvailability.available,
    bool? isSelected,
    this.isDownloaded = false,
  }) : isSelected = isSelected ?? availability.isPlayable;

  final int index; // 1-based position in the original playlist
  final String id; // extractor video/track id
  final String title;
  final String url;
  final Duration? duration;
  final String? uploader;
  final EntryAvailability availability;

  bool isSelected;
  bool isDownloaded;

  /// Only playable entries can ever be selected; unavailable ones are locked.
  bool get isSelectable => availability.isPlayable;

  SelectablePlaylistEntry copyWith({bool? isSelected, bool? isDownloaded}) =>
      SelectablePlaylistEntry(
        index: index,
        id: id,
        title: title,
        url: url,
        duration: duration,
        uploader: uploader,
        availability: availability,
        isSelected: isSelected ?? this.isSelected,
        isDownloaded: isDownloaded ?? this.isDownloaded,
      );
}

/// Owns the selection state for a detected playlist (Feature 1b/1c). Lives in
/// the analysis result, not widget state, so it survives panel rebuilds and is
/// persisted with the queue.
class PlaylistSelection extends ChangeNotifier {
  PlaylistSelection({required this.title, required List<SelectablePlaylistEntry> entries})
    : entries = List.unmodifiable(entries);

  final String title;
  final List<SelectablePlaylistEntry> entries;

  int get total => entries.length;
  int get selectableCount => entries.where((e) => e.isSelectable).length;
  int get selectedCount => entries.where((e) => e.isSelected).length;
  bool get hasSelection => selectedCount > 0;

  List<SelectablePlaylistEntry> get selectedEntries =>
      entries.where((e) => e.isSelected).toList();

  void selectAll() => _apply((e) => e.isSelectable);
  void deselectAll() => _apply((_) => false);
  void invert() => _apply((e) => e.isSelectable && !e.isSelected);

  /// Select exactly the [from..to] span (1-based, inclusive), deselecting the
  /// rest. Non-selectable entries in range stay unselected.
  void selectRange(int from, int to) =>
      _apply((e) => e.isSelectable && e.index >= from && e.index <= to);

  /// "I already downloaded the first N" gesture: select [index..end], drop the
  /// rest.
  void selectFromHere(int index) => selectRange(index, total);

  void setSelected(SelectablePlaylistEntry entry, bool value) {
    if (!entry.isSelectable) return;
    entry.isSelected = value;
    notifyListeners();
  }

  /// Range validity for the From/To fields. Returns null when valid, else an
  /// inline error string.
  String? validateRange(int? from, int? to) {
    if (from == null || to == null) {
      return AppStrings.rangeInvalid.replaceAll('{max}', '$total');
    }
    if (from < 1 || to > total || from > to) {
      return AppStrings.rangeInvalid.replaceAll('{max}', '$total');
    }
    return null;
  }

  void _apply(bool Function(SelectablePlaylistEntry) predicate) {
    for (final e in entries) {
      e.isSelected = predicate(e);
    }
    notifyListeners();
  }
}
