import 'dart:io';

import 'package:down_any_media/models/playlist_selection.dart';
import 'package:down_any_media/services/download_archive.dart';
import 'package:flutter_test/flutter_test.dart';

PlaylistSelection make(int count, {Set<int> unavailable = const {}}) {
  return PlaylistSelection(
    title: 'Test',
    entries: List.generate(count, (i) {
      final idx = i + 1;
      final avail = unavailable.contains(idx)
          ? EntryAvailability.deleted
          : EntryAvailability.available;
      return SelectablePlaylistEntry(
        index: idx,
        id: 'id$idx',
        title: 'Item $idx',
        url: 'https://x/$idx',
        availability: avail,
      );
    }),
  );
}

Set<int> selectedIndices(PlaylistSelection s) =>
    s.selectedEntries.map((e) => e.index).toSet();

void main() {
  group('selection algebra', () {
    test('default selects all playable entries', () {
      final s = make(5);
      expect(s.selectedCount, 5);
      expect(s.selectableCount, 5);
    });

    test('unavailable entries are never selected or selectable', () {
      final s = make(5, unavailable: {2, 4});
      expect(s.selectableCount, 3);
      expect(selectedIndices(s), {1, 3, 5});
      s.selectAll();
      expect(selectedIndices(s), {1, 3, 5}); // 2,4 stay locked out
    });

    test('selectRange 51..100 on a 100-item playlist selects exactly 50', () {
      final s = make(100);
      s.selectRange(51, 100);
      expect(s.selectedCount, 50);
      expect(selectedIndices(s).first, 51);
      expect(selectedIndices(s).last, 100);
    });

    test('selectFromHere selects from index to end and drops earlier', () {
      final s = make(10);
      s.selectRange(1, 10);
      s.selectFromHere(6);
      expect(selectedIndices(s), {6, 7, 8, 9, 10});
    });

    test('invert flips only selectable entries', () {
      final s = make(4, unavailable: {3});
      s.selectRange(1, 2); // {1,2}
      s.invert(); // selectable are 1,2,4 -> now {4}
      expect(selectedIndices(s), {4});
    });

    test('deselectAll then select single', () {
      final s = make(3);
      s.deselectAll();
      expect(s.hasSelection, isFalse);
      s.setSelected(s.entries.first, true);
      expect(selectedIndices(s), {1});
    });

    test('setSelected ignores locked entries', () {
      final s = make(2, unavailable: {2});
      s.setSelected(s.entries[1], true);
      expect(s.entries[1].isSelected, isFalse);
    });
  });

  group('range validation', () {
    test('valid range', () {
      expect(make(100).validateRange(51, 100), isNull);
    });
    test('From > To rejected', () {
      expect(make(100).validateRange(100, 51), isNotNull);
    });
    test('out of range rejected', () {
      expect(make(100).validateRange(0, 100), isNotNull);
      expect(make(100).validateRange(1, 101), isNotNull);
    });
    test('non-numeric (null) rejected', () {
      expect(make(100).validateRange(null, 5), isNotNull);
    });
    test('single-item playlist From=To=1 is valid', () {
      final s = make(1);
      expect(s.validateRange(1, 1), isNull);
      s.selectRange(1, 1);
      expect(s.selectedCount, 1);
    });
  });

  group('availability parsing', () {
    test('private / deleted / unavailable from title', () {
      expect(EntryAvailability.from(title: '[Private video]'),
          EntryAvailability.private);
      expect(EntryAvailability.from(title: '[Deleted video]'),
          EntryAvailability.deleted);
      expect(EntryAvailability.from(availability: 'subscriber_only'),
          EntryAvailability.unavailable);
      expect(EntryAvailability.from(title: 'Normal song'),
          EntryAvailability.available);
    });
  });

  group('download archive', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('dam_archive'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('append then readIds round-trips and dedupes', () async {
      final path = DownloadArchive.pathFor(tmp.path);
      await DownloadArchive.append(path, 'youtube', 'abc');
      await DownloadArchive.append(path, 'youtube', 'abc'); // dup ignored
      await DownloadArchive.append(path, 'youtube', 'def');
      expect(await DownloadArchive.readIds(path), {'abc', 'def'});
    });

    test('missing archive reads as empty', () async {
      final ids = await DownloadArchive.readIds(
        DownloadArchive.pathFor(tmp.path),
      );
      expect(ids, isEmpty);
    });

    test('crossReference marks + auto-deselects when skip is on', () {
      final s = make(4);
      DownloadArchive.crossReference(
        s.entries,
        {'id1', 'id2'},
        skipDownloaded: true,
      );
      expect(s.entries[0].isDownloaded, isTrue);
      expect(s.entries[0].isSelected, isFalse);
      expect(s.entries[2].isDownloaded, isFalse);
      expect(selectedIndices(s), {3, 4}); // first two auto-deselected
    });

    test('crossReference keeps selection when skip is off', () {
      final s = make(2);
      DownloadArchive.crossReference(s.entries, {'id1'}, skipDownloaded: false);
      expect(s.entries[0].isDownloaded, isTrue);
      expect(s.entries[0].isSelected, isTrue); // still selected
    });
  });
}
