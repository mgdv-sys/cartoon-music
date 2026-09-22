import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'track_list_screen.dart';

class RecentlyPlayedScreen extends StatelessWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TrackListScreen(
      title: 'Recently Played',
      loader: () => context.read<AppState>().recentlyPlayed(),
      emptyMessage: 'Nothing played yet.',
    );
  }
}
