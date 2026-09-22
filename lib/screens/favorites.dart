import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'track_list_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TrackListScreen(
      title: 'Favorites',
      loader: () => context.read<AppState>().favorites(),
      emptyMessage: 'Tap the heart on any track to favorite it.',
    );
  }
}
