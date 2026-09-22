import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'track_list_screen.dart';

class AllTracksScreen extends StatelessWidget {
  const AllTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return TrackListScreen(
      title: 'All Tracks',
      loader: () async => app.allTracks,
      emptyMessage: 'Add a music folder from Home to get started.',
      showSort: true,
    );
  }
}
