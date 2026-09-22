import 'package:flutter/material.dart';
import '../library/lyrics_service.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

/// "LYRICS" tab. Shows embedded lyrics if the track has them; otherwise
/// AppState fetches synced lyrics from lrclib.net when online. Synced
/// lyrics highlight the currently-playing line, larger than the rest, and
/// auto-scroll to keep it in view.
class LyricsPanel extends StatefulWidget {
  final ParsedLyrics lyrics;
  final bool loading;
  final Duration position;
  final PaletteColors colors;

  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.loading,
    required this.position,
    required this.colors,
  });

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const double _itemHeight = 44;
  final _controller = ScrollController();
  int _lastIndex = -1;

  int _currentIndexFor(List<LyricLine> lines) {
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= widget.position) index = i;
    }
    return index;
  }

  void _maybeScrollTo(int index) {
    if (index == _lastIndex || !_controller.hasClients) return;
    _lastIndex = index;
    final target = (index * _itemHeight) - 120;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No lyrics found for this track.',
            textAlign: TextAlign.center,
            style: CartoonStyle.body(widget.colors.textColor.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    if (!widget.lyrics.isSynced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              widget.lyrics.plainText ?? '',
              textAlign: TextAlign.center,
              style: CartoonStyle.body(widget.colors.textColor, size: 15),
            ),
          ),
        ),
      );
    }

    final lines = widget.lyrics.syncedLines;
    final currentIndex = _currentIndexFor(lines);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollTo(currentIndex));

    return ListView.builder(
      controller: _controller,
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final isCurrent = i == currentIndex;
        final isPast = i < currentIndex;
        return ConstrainedBox(
          // minHeight (not a fixed height) so lines that wrap to 2-3 rows
          // can grow instead of being painted past a hard-clipped 44px box
          // and getting overdrawn by the next item (the reported "words
          // missing" bug) — short lines still keep the old row rhythm.
          constraints: const BoxConstraints(minHeight: _itemHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedDefaultTextStyle(
                  duration: CartoonStyle.springDuration,
                  textAlign: TextAlign.center,
                  style: CartoonStyle.heading(
                    isCurrent ? Colors.black : widget.colors.textColor.withValues(alpha: isPast ? 0.3 : 0.45),
                    size: isCurrent ? 21 : 16,
                    weight: isCurrent ? FontWeight.w800 : FontWeight.w400,
                  ),
                  child: Text(lines[i].text, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
