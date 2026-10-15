import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../models/playlist_selection.dart';

/// Playlist range & selective-download UI (Feature 1b).
///
/// Selection state lives in [PlaylistSelection] (a ChangeNotifier), not in this
/// widget, so it survives rebuilds and is persisted with the queue.
class PlaylistSelectionPanel extends StatefulWidget {
  const PlaylistSelectionPanel({
    super.key,
    required this.selection,
    required this.onDownload,
    this.downloadLabel = 'Download selected',
  });

  final PlaylistSelection selection;

  /// Null disables the Download button (empty selection).
  final VoidCallback? onDownload;
  final String downloadLabel;

  @override
  State<PlaylistSelectionPanel> createState() => _PlaylistSelectionPanelState();
}

class _PlaylistSelectionPanelState extends State<PlaylistSelectionPanel> {
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _searchController = TextEditingController();
  String? _rangeError;
  String _search = '';

  PlaylistSelection get _selection => widget.selection;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onChanged);
  }

  @override
  void dispose() {
    _selection.removeListener(_onChanged);
    _fromController.dispose();
    _toController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _applyRange() {
    final from = int.tryParse(_fromController.text.trim());
    final to = int.tryParse(_toController.text.trim());
    final error = _selection.validateRange(from, to);
    setState(() => _rangeError = error);
    if (error == null) {
      _selection.selectRange(from!, to!);
    }
  }

  List<SelectablePlaylistEntry> get _visibleEntries {
    if (_search.isEmpty) return _selection.entries;
    final q = _search.toLowerCase();
    return _selection.entries
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _selection;
    final canDownload = sel.hasSelection && widget.onDownload != null;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              sel.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sel.selectedCount} of ${sel.total} selected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Range controls
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _fromController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'From',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _toController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _applyRange,
                  child: const Text('Apply'),
                ),
              ],
            ),
            if (_rangeError != null) ...[
              const SizedBox(height: 6),
              Text(
                _rangeError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Quick actions
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: sel.selectAll,
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: sel.deselectAll,
                  child: const Text('Deselect all'),
                ),
                TextButton(
                  onPressed: sel.invert,
                  child: const Text('Invert'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Search filter
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter items',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 8),
            // Entry list (virtualized)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _visibleEntries.length,
                itemBuilder: (context, i) => _EntryTile(
                  entry: _visibleEntries[i],
                  onToggle: (v) => sel.setSelected(_visibleEntries[i], v),
                  onSelectFromHere: () =>
                      sel.selectFromHere(_visibleEntries[i].index),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: canDownload ? '' : AppStrings.selectAtLeastOne,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canDownload ? widget.onDownload : null,
                  icon: const Icon(Icons.download),
                  label: Text('${widget.downloadLabel} (${sel.selectedCount})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onToggle,
    required this.onSelectFromHere,
  });

  final SelectablePlaylistEntry entry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSelectFromHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = !entry.isSelectable;
    final subtitleParts = <String>[
      if (entry.duration != null) _formatDuration(entry.duration!),
      if (entry.uploader != null && entry.uploader!.isNotEmpty) entry.uploader!,
    ];

    return InkWell(
      onLongPress: locked ? null : onSelectFromHere,
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Row(
          children: [
            Checkbox(
              value: entry.isSelected,
              onChanged: locked ? null : (v) => onToggle(v ?? false),
            ),
            SizedBox(
              width: 36,
              child: Text(
                entry.index.toString().padLeft(2, '0'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (entry.availability.badge != null)
              _Badge(entry.availability.badge!, theme.colorScheme.error),
            if (entry.isDownloaded)
              _Badge(AppStrings.badgeDownloaded, theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
