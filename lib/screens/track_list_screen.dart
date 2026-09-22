import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../widgets/cartoon_button.dart';
import '../widgets/track_row.dart';

enum TrackSort { titleAsc, artistAsc, albumAsc, durationAsc, recentlyAdded }

const Map<TrackSort, String> kSortLabels = {
  TrackSort.titleAsc: 'Title (A–Z)',
  TrackSort.artistAsc: 'Artist (A–Z)',
  TrackSort.albumAsc: 'Album (A–Z)',
  TrackSort.durationAsc: 'Duration',
  TrackSort.recentlyAdded: 'Recently added',
};

/// Generic "list of tracks with Play/Shuffle/Sort at top" screen, reused for
/// All Tracks, Most Played, Recently Played, Favorites, and playlists.
class TrackListScreen extends StatefulWidget {
  final String title;
  final Future<List<LibraryTrack>> Function() loader;
  final String emptyMessage;
  final void Function(LibraryTrack track)? onRemove;
  final bool showSort;
  final bool showPlayCount;

  const TrackListScreen({
    super.key,
    required this.title,
    required this.loader,
    this.emptyMessage = 'Nothing here yet.',
    this.onRemove,
    this.showSort = false,
    this.showPlayCount = false,
  });

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  List<LibraryTrack> _tracks = [];
  bool _loading = true;
  TrackSort _sort = TrackSort.titleAsc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TrackListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tracks = await widget.loader();
    if (!mounted) return;
    setState(() {
      // Screens without a sort menu (Most Played, Recently Played,
      // Playlists, Favorites) have a meaningful order from their loader
      // (play count, recency, manual order) — only re-sort when the user
      // can actually pick a sort, otherwise that order was getting silently
      // clobbered by the titleAsc default below.
      _tracks = widget.showSort ? _sorted(tracks) : tracks;
      _loading = false;
    });
  }

  List<LibraryTrack> _sorted(List<LibraryTrack> input) {
    final list = List<LibraryTrack>.from(input);
    switch (_sort) {
      case TrackSort.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case TrackSort.artistAsc:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case TrackSort.albumAsc:
        list.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
      case TrackSort.durationAsc:
        list.sort((a, b) => a.duration.compareTo(b.duration));
      case TrackSort.recentlyAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
    return list;
  }

  void _setSort(TrackSort sort) {
    setState(() {
      _sort = sort;
      _tracks = _sorted(_tracks);
    });
  }

  Duration get _totalDuration => _tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.title, style: CartoonStyle.heading(colors.textColor, size: 28)),
              const Spacer(),
              if (widget.showSort)
                PopupMenuButton<TrackSort>(
                  initialValue: _sort,
                  onSelected: _setSort,
                  itemBuilder: (context) => TrackSort.values
                      .map((s) => PopupMenuItem(value: s, child: Text(kSortLabels[s]!)))
                      .toList(),
                  child: CartoonButton(
                    fill: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onPressed: null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(kSortLabels[_sort]!, style: CartoonStyle.body(Colors.black, size: 13)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              CartoonButton(
                fill: colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                onPressed: _tracks.isEmpty ? null : () => app.playTrack(_tracks.first, contextQueue: _tracks),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text('Play', style: CartoonStyle.body(Colors.white, size: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CartoonButton(
                fill: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                onPressed: _tracks.isEmpty
                    ? null
                    : () {
                        final shuffled = List<LibraryTrack>.from(_tracks)..shuffle();
                        app.playTrack(shuffled.first, contextQueue: shuffled);
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shuffle_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text('Shuffle', style: CartoonStyle.body(Colors.black, size: 13)),
                  ],
                ),
              ),
              if (_tracks.any((t) => t.isYoutubeStream)) ...[
                const SizedBox(width: 10),
                CartoonButton(
                  fill: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  onPressed: app.downloadingYoutubePlaylist ? null : () => app.startBulkYoutubeDownload(_tracks),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('Download all', style: CartoonStyle.body(Colors.black, size: 13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (!_loading && _tracks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'} • ${CartoonStyle.formatTotalDuration(_totalDuration)}',
              style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 12),
            ),
          ],
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_tracks.isEmpty)
            Text(widget.emptyMessage, style: CartoonStyle.body(colors.textColor))
          else
            for (final track in _tracks)
              TrackRow(
                track: track,
                isCurrent: app.currentTrack?.id == track.id,
                onTap: () => app.playTrack(track, contextQueue: _tracks),
                showPlayCount: widget.showPlayCount,
                trailing: widget.onRemove == null
                    ? null
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                        onPressed: () {
                          widget.onRemove!(track);
                          _load();
                        },
                      ),
              ),
        ],
      ),
    );
  }
}
