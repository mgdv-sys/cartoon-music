import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'playback_bar.dart';

/// Desktop docked mini player: the shared [PlaybackBar] content, pinned to
/// the bottom of every screen via [PlaybackScaffold]. Tapping anywhere on
/// the bar (outside the interactive controls) opens the full Now Playing
/// screen.
class TransportBar extends StatelessWidget {
  final AppState app;
  final VoidCallback onExpand;

  const TransportBar({super.key, required this.app, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final colors = app.colors;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onExpand,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border(top: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
        ),
        child: PlaybackBar(app: app, onChevronTap: onExpand),
      ),
    );
  }
}
