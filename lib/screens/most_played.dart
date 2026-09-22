import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'track_list_screen.dart';

class MostPlayedScreen extends StatelessWidget {
  const MostPlayedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TrackListScreen(
      title: 'Most Played',
      loader: () => context.read<AppState>().mostPlayed(),
      emptyMessage: 'Play some tracks and they\'ll show up here.',
      showPlayCount: true,
    );
  }
}
