import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import '../widgets/playback_bar.dart';
import '../widgets/queue_panel.dart';
import '../widgets/lyrics_panel.dart';
import 'artist_detail.dart';

/// Now-Playing screen, laid out per the reference sketch:
///
///   +--------------------+-----------+
///   | Album cover         | Queue     |
///   | Lyrics (scrolls)    | here      |
///   +--------------------+-----------+
///   | <  (>)  >   0:00 ~~~~~~ 1:00  volume |
///   +---------------------------------+
///
/// Wide windows show album+lyrics beside the queue; narrow windows stack
/// album/lyrics on top with the queue reachable below (no room for a third
/// simultaneous column).
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to a post-frame callback: calling this synchronously here
    // triggers AppState.notifyListeners() while this route's own build (and
    // the pushing route's) is still in flight, which Flutter flags as
    // "setState() called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      final track = app.currentTrack;
      // Covers the app-restart case: a restored "now playing" track has no
      // lyrics loaded yet since restore doesn't trigger playback.
      if (track != null && app.currentLyrics.isEmpty && !app.loadingLyrics) {
        app.loadLyricsFor(track);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        flexibleSpace: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'NOW PLAYING',
          style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.7), size: 12).copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colors.accent,
              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 700;
                final albumAndLyrics = _AlbumAndLyrics(app: app, colors: colors);

                // A live radio stream has no queue to show.
                if (app.currentRadioStation != null) return albumAndLyrics;

                final queue = _QueueColumn(app: app, colors: colors);

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: albumAndLyrics),
                      Container(width: 380, decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
                      ), child: queue),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: albumAndLyrics),
                    Container(
                      height: 360,
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
                      ),
                      child: queue,
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(top: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
            ),
            child: PlaybackBar(app: app),
          ),
        ],
      ),
    );
  }
}

/// Left side: the album cover fills the whole area full-size, with the
/// lyrics floating in front of it as a translucent panel — the art stays
/// visible behind/around the text rather than being pushed out of the way.
class _AlbumAndLyrics extends StatelessWidget {
  final AppState app;
  final PaletteColors colors;
  const _AlbumAndLyrics({required this.app, required this.colors});

  @override
  Widget build(BuildContext context) {
    final track = app.currentTrack;
    final isRadio = app.currentRadioStation != null;
    final hasLyrics = !isRadio && !app.loadingLyrics && !app.currentLyrics.isEmpty;

    final textShadow = const [Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1))];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
                    border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThick),
                    image: track?.artworkPath != null
                        ? DecorationImage(image: FileImage(File(track!.artworkPath!)), fit: BoxFit.cover)
                        : null,
                  ),
                  child: track?.artworkPath == null
                      ? Center(
                          child: Icon(
                            isRadio ? Icons.radio_rounded : Icons.music_note_rounded,
                            size: 96,
                            color: kOutlineColor,
                          ),
                        )
                      : null,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.nowPlayingTitle,
                      style: CartoonStyle.heading(Colors.white, size: 18).copyWith(shadows: textShadow),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: track == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: track.artist)),
                              ),
                      child: Text(
                        app.nowPlayingSubtitle,
                        style: CartoonStyle.body(Colors.white, size: 13).copyWith(shadows: textShadow),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasLyrics)
                Positioned(
                  left: constraints.maxWidth * 0.14,
                  right: constraints.maxWidth * 0.14,
                  top: constraints.maxHeight * 0.16,
                  bottom: constraints.maxHeight * 0.1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: (colors.isDark ? Colors.black : Colors.white).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
                      border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    padding: const EdgeInsets.all(16),
                    child: LyricsPanel(
                      lyrics: app.currentLyrics,
                      loading: app.loadingLyrics,
                      position: app.position,
                      colors: colors,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Right side (or bottom, on narrow layouts): just the queue, no tabs.
class _QueueColumn extends StatelessWidget {
  final AppState app;
  final PaletteColors colors;
  const _QueueColumn({required this.app, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QUEUE', style: CartoonStyle.heading(colors.textColor, size: 14)),
          const SizedBox(height: 10),
          Expanded(child: QueuePanel(app: app)),
        ],
      ),
    );
  }
}

