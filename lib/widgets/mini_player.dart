import 'dart:io';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'cartoon_button.dart';
import 'equalizer.dart';

/// Android compact mini-player, docked above the bottom nav bar. Tap to
/// expand into the full Now-Playing screen.
class MiniPlayer extends StatelessWidget {
  final AppState app;
  final VoidCallback onExpand;

  const MiniPlayer({super.key, required this.app, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final colors = app.colors;
    final track = app.currentTrack;
    if (!app.hasNowPlaying) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onExpand,
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
          border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThick),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kOutlineColor, width: 1.5),
                image: track?.artworkPath != null
                    ? DecorationImage(image: FileImage(File(track!.artworkPath!)), fit: BoxFit.cover)
                    : null,
              ),
              child: track == null ? const Icon(Icons.radio_rounded, color: Colors.black45) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.nowPlayingTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(colors.textColor, size: 13).copyWith(fontWeight: FontWeight.w500)),
                  Text(app.nowPlayingSubtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.65), size: 11)),
                ],
              ),
            ),
            EqualizerBars(isPlaying: app.isPlaying, colors: colors.equalizerColors, height: 18),
            const SizedBox(width: 8),
            CartoonButton(
              circular: true,
              fill: colors.accent,
              padding: const EdgeInsets.all(8),
              onPressed: app.togglePlayPause,
              child: Icon(
                app.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
