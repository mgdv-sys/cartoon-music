import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/edit_track_screen.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'track_actions.dart';

/// A single track row used across All Tracks, Most Played, Recently Played,
/// Favorites, playlists, album detail, and search results.
class TrackRow extends StatelessWidget {
  final LibraryTrack track;
  final bool isCurrent;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showPlayCount;

  const TrackRow({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.onTap,
    this.trailing,
    this.showPlayCount = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isCurrent ? colors.accent.withValues(alpha: 0.16) : Colors.white,
          borderRadius: BorderRadius.circular(CartoonStyle.radiusSmall),
          border: Border.all(
            color: kOutlineColor,
            width: isCurrent ? CartoonStyle.outlineThick : CartoonStyle.outlineThin,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kOutlineColor, width: 1.5),
                image: track.artworkPath != null
                    ? DecorationImage(image: FileImage(File(track.artworkPath!)), fit: BoxFit.cover)
                    : null,
              ),
              child: track.artworkPath == null
                  ? const Icon(Icons.music_note_rounded, size: 20, color: kOutlineColor)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(Colors.black, size: 14).copyWith(fontWeight: FontWeight.w500)),
                  Text('${track.artist} • ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(Colors.black54, size: 12)),
                ],
              ),
            ),
            if (showPlayCount) ...[
              Icon(Icons.play_circle_outline_rounded, size: 14, color: Colors.black45),
              const SizedBox(width: 4),
              Text(
                '${track.playCount}',
                style: CartoonStyle.body(Colors.black54, size: 12),
              ),
              const SizedBox(width: 10),
            ],
            Text(_fmt(track.duration), style: CartoonStyle.body(Colors.black54, size: 12)),
            const SizedBox(width: 8),
            if (app.downloadingYoutubeTrackIds.contains(track.id))
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: track.isFavorite ? colors.accent : Colors.black45,
                size: 20,
              ),
              onPressed: () => app.toggleFavorite(track),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (value) {
                if (value == 'play_next') {
                  app.playNext(track);
                } else if (value == 'add_queue') {
                  app.addToQueue(track);
                } else if (value == 'edit') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EditTrackScreen(track: track)),
                  );
                } else if (value == 'delete') {
                  confirmDeleteTrack(context, track);
                } else if (value == 'download') {
                  app.downloadYoutubeTrack(track).then((_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Downloaded to your library.')));
                    }
                  }).catchError((e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Couldn't download: ${e.toString().replaceFirst('Exception: ', '')}")),
                      );
                    }
                  });
                } else if (value.startsWith('playlist:')) {
                  final playlistId = int.parse(value.substring('playlist:'.length));
                  app.addTrackToPlaylist(playlistId, track);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'play_next', child: Text('Play next')),
                const PopupMenuItem(value: 'add_queue', child: Text('Add to queue')),
                const PopupMenuDivider(),
                if (app.playlists.isEmpty)
                  const PopupMenuItem(enabled: false, child: Text('No playlists yet'))
                else
                  ...app.playlists.map(
                    (p) => PopupMenuItem(value: 'playlist:${p.id}', child: Text('Add to ${p.name}')),
                  ),
                const PopupMenuDivider(),
                if (track.isYoutubeStream)
                  PopupMenuItem(
                    value: 'download',
                    enabled: !app.downloadingYoutubeTrackIds.contains(track.id),
                    child: const Text('Download to library'),
                  ),
                const PopupMenuItem(value: 'edit', child: Text('Edit metadata')),
                const PopupMenuItem(value: 'delete', child: Text('Delete song', style: TextStyle(color: Colors.red))),
              ],
            ),
            ?trailing,
            if (isCurrent) Icon(Icons.equalizer_rounded, color: colors.accent, size: 20),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
