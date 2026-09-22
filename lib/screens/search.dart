import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../widgets/track_row.dart';

/// Search results view, driven by the top bar's search field, searching the
/// local library (title/artist/album) rather than any streaming service.
class SearchScreen extends StatefulWidget {
  final String query;
  const SearchScreen({super.key, required this.query});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  List<LibraryTrack> _results = [];
  bool _loading = false;
  String _lastQueried = '';

  Duration get _totalDuration => _results.fold(Duration.zero, (sum, t) => sum + t.duration);

  @override
  void initState() {
    super.initState();
    _maybeSearch();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) _maybeSearch();
  }

  Future<void> _maybeSearch() async {
    if (widget.query.trim().isEmpty || widget.query == _lastQueried) return;
    _lastQueried = widget.query;
    setState(() => _loading = true);
    final results = await context.read<AppState>().searchTracks(widget.query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Results for "${widget.query}"', style: CartoonStyle.heading(colors.textColor, size: 22)),
          if (!_loading && _results.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_results.length} ${_results.length == 1 ? 'song' : 'songs'} • ${CartoonStyle.formatTotalDuration(_totalDuration)}',
              style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.55), size: 12),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_results.isEmpty)
            Text('No results.', style: CartoonStyle.body(colors.textColor))
          else
            Expanded(
              child: ListView(
                children: [
                  for (final track in _results)
                    TrackRow(
                      track: track,
                      isCurrent: app.currentTrack?.id == track.id,
                      onTap: () => app.playTrack(track, contextQueue: _results),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
