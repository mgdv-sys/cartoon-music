import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import '../widgets/cartoon_button.dart';
import '../widgets/playback_scaffold.dart';
import '../widgets/track_actions.dart';
import 'edit_track_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  final LibraryAlbum album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<LibraryTrack> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracks = await context.read<AppState>().tracksForAlbum(widget.album.id);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  Duration get _totalDuration => _tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  String _fmtTrack(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool _albumIsCurrent(AppState app) => app.currentTrack?.albumId == widget.album.id;

  void _playAlbum(AppState app) {
    if (_tracks.isEmpty) return;
    if (_albumIsCurrent(app)) {
      app.togglePlayPause();
    } else {
      app.playTrack(_tracks.first, contextQueue: _tracks);
    }
  }

  void _shuffleAlbum(AppState app) {
    if (_tracks.isEmpty) return;
    if (!app.shuffle) app.toggleShuffle();
    final shuffled = List<LibraryTrack>.from(_tracks)..shuffle();
    app.playTrack(shuffled.first, contextQueue: shuffled);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return PlaybackScaffold(
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete album',
            onPressed: () async {
              final deleted = await confirmDeleteAlbum(context, widget.album, _tracks.length);
              if (deleted && context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final info = _AlbumInfoPanel(
                  album: widget.album,
                  tracks: _tracks,
                  totalDuration: _tracks.isEmpty ? null : CartoonStyle.formatTotalDuration(_totalDuration),
                  app: app,
                  colors: colors,
                  isPlaying: _albumIsCurrent(app) && app.isPlaying,
                  onPlay: () => _playAlbum(app),
                  onShuffle: () => _shuffleAlbum(app),
                  wide: isWide,
                );

                final trackList = ListView.builder(
                  padding: EdgeInsets.fromLTRB(isWide ? 12 : 20, isWide ? 20 : 0, 20, 20),
                  itemCount: _tracks.length,
                  itemBuilder: (context, i) => _TrackCard(
                    track: _tracks[i],
                    releaseYear: widget.album.releaseYear,
                    isCurrent: app.currentTrack?.id == _tracks[i].id,
                    onTap: () => app.playTrack(_tracks[i], contextQueue: _tracks),
                    formatDuration: _fmtTrack,
                    colors: colors,
                    onEdited: _load,
                  ),
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 280, child: SingleChildScrollView(child: info)),
                      Expanded(child: trackList),
                    ],
                  );
                }
                return Column(
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: info),
                    Expanded(child: trackList),
                  ],
                );
              },
            ),
    );
  }
}

/// Left/top panel: cover art, title/artist, stats line, and the
/// shuffle/play/repeat trio — matches the reference layout's playlist info
/// column.
class _AlbumInfoPanel extends StatelessWidget {
  final LibraryAlbum album;
  final List<LibraryTrack> tracks;
  final String? totalDuration;
  final AppState app;
  final PaletteColors colors;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool wide;

  const _AlbumInfoPanel({
    required this.album,
    required this.tracks,
    required this.totalDuration,
    required this.app,
    required this.colors,
    required this.isPlaying,
    required this.onPlay,
    required this.onShuffle,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final trackCount = tracks.length;
    final hasStreamedTracks = tracks.any((t) => t.isYoutubeStream);
    final statsParts = [
      '$trackCount ${trackCount == 1 ? 'song' : 'songs'}',
      if (totalDuration != null) totalDuration!,
      if (album.releaseYear != null) '${album.releaseYear}',
    ];

    final cover = Container(
      width: wide ? 220 : 140,
      height: wide ? 220 : 140,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
        border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThick),
        image: album.artworkPath != null
            ? DecorationImage(image: FileImage(File(album.artworkPath!)), fit: BoxFit.cover)
            : null,
      ),
      child: album.artworkPath == null ? const Icon(Icons.album_rounded, size: 48, color: kOutlineColor) : null,
    );

    final controls = Row(
      mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        CartoonButton(
          circular: true,
          fill: app.shuffle ? colors.supportingAccents[0] : Colors.white,
          padding: const EdgeInsets.all(10),
          onPressed: trackCount == 0 ? null : onShuffle,
          child: Icon(Icons.shuffle_rounded, size: 18, color: app.shuffle ? Colors.white : Colors.black),
        ),
        const SizedBox(width: 12),
        CartoonButton(
          circular: true,
          fill: colors.accent,
          padding: const EdgeInsets.all(14),
          onPressed: trackCount == 0 ? null : onPlay,
          child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        CartoonButton(
          circular: true,
          fill: app.repeat ? colors.supportingAccents[2 % colors.supportingAccents.length] : Colors.white,
          padding: const EdgeInsets.all(10),
          onPressed: app.toggleRepeat,
          child: Icon(Icons.repeat_rounded, size: 18, color: app.repeat ? Colors.white : Colors.black),
        ),
        if (hasStreamedTracks) ...[
          const SizedBox(width: 12),
          CartoonButton(
            circular: true,
            fill: Colors.white,
            padding: const EdgeInsets.all(10),
            onPressed: app.downloadingYoutubePlaylist ? null : () => app.startBulkYoutubeDownload(tracks),
            child: const Icon(Icons.download_rounded, size: 18, color: Colors.black),
          ),
        ],
      ],
    );

    if (!wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          cover,
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.name, style: CartoonStyle.heading(colors.textColor, size: 22)),
                Text(album.artist, style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.7))),
                const SizedBox(height: 4),
                Text(statsParts.join(' • '), style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 12)),
                const SizedBox(height: 12),
                controls,
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          cover,
          const SizedBox(height: 16),
          Text(
            album.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: CartoonStyle.heading(colors.textColor, size: 18),
          ),
          const SizedBox(height: 2),
          Text(album.artist, textAlign: TextAlign.center, style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.7), size: 13)),
          const SizedBox(height: 4),
          Text(
            statsParts.join(' • '),
            textAlign: TextAlign.center,
            style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 11),
          ),
          const SizedBox(height: 16),
          controls,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A single track row rendered as a bordered card — highlighted with the
/// accent color when it's the current track — with a play-count badge,
/// duration, and the album's release year on the trailing side.
class _TrackCard extends StatelessWidget {
  final LibraryTrack track;
  final int? releaseYear;
  final bool isCurrent;
  final VoidCallback onTap;
  final String Function(Duration) formatDuration;
  final PaletteColors colors;
  final VoidCallback onEdited;

  const _TrackCard({
    required this.track,
    required this.releaseYear,
    required this.isCurrent,
    required this.onTap,
    required this.formatDuration,
    required this.colors,
    required this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final textColor = isCurrent ? colors.accent : colors.textColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(CartoonStyle.radiusSmall),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isCurrent ? colors.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(CartoonStyle.radiusSmall),
            border: Border.all(
              color: isCurrent ? colors.accent : Colors.transparent,
              width: CartoonStyle.outlineThin,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Icon(
                  isCurrent ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                  color: isCurrent ? colors.accent : colors.textColor.withValues(alpha: 0.4),
                  size: 18,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(textColor, size: 14)
                          .copyWith(fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 12),
                    ),
                  ],
                ),
              ),
              if (track.playCount > 0) ...[
                Icon(Icons.play_arrow_rounded, color: colors.accent, size: 14),
                const SizedBox(width: 2),
                Text('${track.playCount}', style: CartoonStyle.body(colors.accent, size: 12)),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatDuration(track.duration), style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.6), size: 12)),
                  if (releaseYear != null)
                    Text('$releaseYear', style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.4), size: 11)),
                ],
              ),
              const SizedBox(width: 4),
              if (app.downloadingYoutubeTrackIds.contains(track.id))
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: track.isFavorite ? colors.accent : colors.textColor.withValues(alpha: 0.4),
                  size: 18,
                ),
                onPressed: () => app.toggleFavorite(track),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 18, color: colors.textColor.withValues(alpha: 0.7)),
                onSelected: (value) async {
                  if (value == 'play_next') {
                    app.playNext(track);
                  } else if (value == 'add_queue') {
                    app.addToQueue(track);
                  } else if (value == 'edit') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EditTrackScreen(track: track)),
                    );
                    onEdited();
                  } else if (value == 'delete') {
                    await confirmDeleteTrack(context, track);
                    onEdited();
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
            ],
          ),
        ),
      ),
    );
  }
}
