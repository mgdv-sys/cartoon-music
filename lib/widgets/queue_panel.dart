import 'dart:io';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

/// Queue page: a header with the Save-as-playlist button, then two tabs —
/// "Up Next" (the rest of the upcoming queue, reorderable) and "Previously
/// Played" (everything already played, most recent first).
class QueuePanel extends StatefulWidget {
  final AppState app;
  const QueuePanel({super.key, required this.app});

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  int _tab = 0; // 0 = Up Next, 1 = Previously Played

  AppState get app => widget.app;

  Future<void> _saveAsPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save queue as playlist'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final playlistId = await app.createPlaylist(name);
    for (final track in app.queue) {
      await app.addTrackToPlaylist(playlistId, track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = app.colors;
    final currentIndex = app.queueIndex;
    final upcoming = currentIndex >= 0 ? app.queue.sublist(currentIndex + 1) : app.queue;
    final played = currentIndex > 0 ? app.queue.sublist(0, currentIndex).reversed.toList() : const <LibraryTrack>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Playing from Queue',
                      style: CartoonStyle.body(colors.textColor, size: 13).copyWith(fontWeight: FontWeight.w500)),
                  if (app.queue.isNotEmpty)
                    Text(
                      '${app.queue.length} ${app.queue.length == 1 ? 'song' : 'songs'} • '
                      '${CartoonStyle.formatTotalDuration(app.queue.fold(Duration.zero, (sum, t) => sum + t.duration))}',
                      style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 11),
                    ),
                ],
              ),
            ),
            if (app.queue.any((t) => t.isYoutubeStream))
              IconButton(
                tooltip: 'Download all',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.download_rounded, size: 20),
                onPressed: app.downloadingYoutubePlaylist ? null : () => app.startBulkYoutubeDownload(app.queue),
              ),
            OutlinedButton(
              onPressed: app.queue.isEmpty ? null : () => _saveAsPlaylist(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThin),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CartoonStyle.radiusChip)),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
        if (app.queue.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTabSelector(colors, upcoming.length, played.length),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: app.queue.isEmpty
              ? Text('Queue is empty.', style: CartoonStyle.body(colors.textColor))
              : _tab == 0
                  ? _buildUpNext(colors, currentIndex, upcoming)
                  : _buildHistory(colors, played),
        ),
      ],
    );
  }

  Widget _buildTabSelector(PaletteColors colors, int upNextCount, int historyCount) {
    return Row(
      children: [
        Expanded(child: _tabChip(label: 'Up Next ($upNextCount)', selected: _tab == 0, colors: colors, onTap: () => setState(() => _tab = 0))),
        const SizedBox(width: 8),
        Expanded(child: _tabChip(label: 'Previously Played ($historyCount)', selected: _tab == 1, colors: colors, onTap: () => setState(() => _tab = 1))),
      ],
    );
  }

  Widget _tabChip({required String label, required bool selected, required PaletteColors colors, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.22) : Colors.white,
          borderRadius: BorderRadius.circular(CartoonStyle.radiusChip),
          border: Border.all(color: kOutlineColor, width: selected ? CartoonStyle.outlineThick : CartoonStyle.outlineThin),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: CartoonStyle.body(Colors.black, size: 12).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
        ),
      ),
    );
  }

  Widget _buildUpNext(PaletteColors colors, int currentIndex, List<LibraryTrack> upcoming) {
    if (upcoming.isEmpty) {
      return Text('No more songs queued.', style: CartoonStyle.body(colors.textColor));
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: upcoming.length,
      onReorderItem: (oldIndex, newIndex) {
        final offset = currentIndex + 1;
        app.reorderQueue(offset + oldIndex, offset + newIndex);
      },
      itemBuilder: (context, i) {
        final track = upcoming[i];
        return _trackTile(
          key: ValueKey('upnext-${track.id}-$i'),
          colors: colors,
          track: track,
          dragIndex: i,
        );
      },
    );
  }

  Widget _buildHistory(PaletteColors colors, List<LibraryTrack> played) {
    if (played.isEmpty) {
      return Text('Nothing played yet.', style: CartoonStyle.body(colors.textColor));
    }
    return ListView.builder(
      itemCount: played.length,
      itemBuilder: (context, i) {
        final track = played[i];
        return _trackTile(
          key: ValueKey('history-${track.id}-$i'),
          colors: colors,
          track: track,
          dragIndex: null,
        );
      },
    );
  }

  Widget _trackTile({
    required Key key,
    required PaletteColors colors,
    required LibraryTrack track,
    required int? dragIndex,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => app.playTrack(track, contextQueue: app.queue),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(CartoonStyle.radiusSmall),
            border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
          ),
          child: Row(
            children: [
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.drag_indicator_rounded, color: Colors.black45, size: 20),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.history_rounded, color: Colors.black26, size: 20),
                ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kOutlineColor, width: 1.5),
                  image: track.artworkPath != null
                      ? DecorationImage(image: FileImage(File(track.artworkPath!)), fit: BoxFit.cover)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: CartoonStyle.body(Colors.black, size: 13).copyWith(fontWeight: FontWeight.w500)),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: CartoonStyle.body(Colors.black54, size: 11)),
                  ],
                ),
              ),
              Text(_formatDuration(track.duration), style: CartoonStyle.body(Colors.black54, size: 11)),
              if (app.downloadingYoutubeTrackIds.contains(track.id))
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: track.isFavorite ? colors.accent : Colors.black45,
                  size: 18,
                ),
                onPressed: () => app.toggleFavorite(track),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.playlist_add_rounded, size: 18, color: Colors.black45),
                onSelected: (value) {
                  if (value == 'download') {
                    final ctx = context;
                    app.downloadYoutubeTrack(track).then((_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(const SnackBar(content: Text('Downloaded to your library.')));
                      }
                    }).catchError((e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text("Couldn't download: ${e.toString().replaceFirst('Exception: ', '')}")),
                        );
                      }
                    });
                    return;
                  }
                  final playlistId = int.parse(value.substring('playlist:'.length));
                  app.addTrackToPlaylist(playlistId, track);
                },
                itemBuilder: (context) => [
                  if (track.isYoutubeStream) ...[
                    PopupMenuItem(
                      value: 'download',
                      enabled: !app.downloadingYoutubeTrackIds.contains(track.id),
                      child: const Text('Download to library'),
                    ),
                    const PopupMenuDivider(),
                  ],
                  if (app.playlists.isEmpty)
                    const PopupMenuItem(enabled: false, child: Text('No playlists yet'))
                  else
                    ...app.playlists.map((p) => PopupMenuItem(value: 'playlist:${p.id}', child: Text('Add to ${p.name}'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
