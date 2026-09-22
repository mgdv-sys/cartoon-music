import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/playback_scaffold.dart';
import 'track_list_screen.dart';

/// All songs by one artist, across every album — reuses [TrackListScreen]
/// the same way a playlist's track list does.
class ArtistDetailScreen extends StatelessWidget {
  final String artistName;
  const ArtistDetailScreen({super.key, required this.artistName});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;
    return PlaybackScaffold(
      appBar: AppBar(backgroundColor: colors.background, elevation: 0, title: Text(artistName)),
      body: TrackListScreen(
        title: artistName,
        loader: () async => app.allTracks.where((t) => t.artist == artistName).toList(),
        emptyMessage: 'No songs by this artist.',
        showSort: true,
      ),
    );
  }
}
