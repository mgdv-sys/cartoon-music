import 'dart:io';
import 'package:flutter/material.dart';
import '../screens/artist_detail.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'cartoon_button.dart';
import 'waveform_seekbar.dart';

/// The playback bar content — track info, the five round transport buttons,
/// favorite/volume, and the colorful waveform scrubber underneath. Shared
/// between the docked desktop mini player ([TransportBar]) and the bottom of
/// the expanded Now Playing screen, so both stay visually identical. Lays
/// out as one row on wide windows; stacks into three rows (dropping the
/// volume slider) on a phone-width screen.
class PlaybackBar extends StatelessWidget {
  final AppState app;
  final VoidCallback? onChevronTap;

  const PlaybackBar({super.key, required this.app, this.onChevronTap});

  @override
  Widget build(BuildContext context) {
    final colors = app.colors;
    final track = app.currentTrack;
    final isRadio = app.currentRadioStation != null;

    final trackInfo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
            image: track?.artworkPath != null
                ? DecorationImage(image: FileImage(File(track!.artworkPath!)), fit: BoxFit.cover)
                : null,
          ),
          child: track == null
              ? Icon(isRadio ? Icons.radio_rounded : Icons.music_note_rounded, color: Colors.black45, size: 20)
              : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                app.nowPlayingTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CartoonStyle.body(colors.textColor, size: 14).copyWith(fontWeight: FontWeight.w600),
              ),
              if (app.hasNowPlaying)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: track == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ArtistDetailScreen(artistName: track.artist)),
                          ),
                  child: Text(
                    app.nowPlayingSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.6), size: 12),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.expand_less_rounded, size: 16, color: colors.textColor.withValues(alpha: 0.6)),
          onPressed: onChevronTap,
        ),
      ],
    );

    final transportButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          icon: Icons.shuffle_rounded,
          fill: app.shuffle ? colors.supportingAccents[0] : Colors.white,
          iconColor: app.shuffle ? Colors.white : Colors.black,
          onPressed: isRadio ? null : app.toggleShuffle,
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.skip_previous_rounded,
          fill: Colors.white,
          onPressed: isRadio ? null : app.skipPrevious,
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: app.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          fill: colors.accent,
          iconColor: Colors.white,
          size: 44,
          onPressed: !app.hasNowPlaying ? null : app.togglePlayPause,
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.skip_next_rounded,
          fill: Colors.white,
          onPressed: isRadio ? null : app.skipNext,
        ),
        const SizedBox(width: 8),
        _RoundButton(
          icon: Icons.repeat_rounded,
          fill: app.repeat ? colors.supportingAccents[2 % colors.supportingAccents.length] : Colors.white,
          iconColor: app.repeat ? Colors.white : Colors.black,
          onPressed: isRadio ? null : app.toggleRepeat,
        ),
      ],
    );

    final favoriteButton = track == null
        ? null
        : _RoundButton(
            icon: track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            fill: track.isFavorite ? colors.accent : Colors.white,
            iconColor: track.isFavorite ? Colors.white : Colors.black,
            size: 32,
            onPressed: () => app.toggleFavorite(track),
          );

    final volume = SizedBox(
      width: 90,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: colors.supportingAccents[0],
          inactiveTrackColor: Colors.black12,
          thumbColor: colors.supportingAccents[0],
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(value: app.volume, onChanged: app.setVolume),
      ),
    );

    final waveformRow = isRadio
        ? Row(
            children: [
              Icon(Icons.podcasts_rounded, size: 16, color: colors.accent),
              const SizedBox(width: 6),
              Text(
                app.radioReconnecting ? 'Reconnecting...' : 'LIVE',
                style: CartoonStyle.body(colors.textColor, size: 12).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          )
        : Row(
            children: [
              Text(_fmt(app.position), style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.6), size: 11)),
              const SizedBox(width: 10),
              Expanded(
                child: WaveformSeekBar(
                  position: app.position,
                  duration: app.duration,
                  barColors: colors.equalizerColors,
                  seed: track?.id ?? 0,
                  dotColor: colors.textColor,
                  onSeek: app.seek,
                  isPlaying: app.isPlaying,
                ),
              ),
              const SizedBox(width: 10),
              Text(_fmt(app.duration), style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.6), size: 11)),
            ],
          );

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 640;

      if (isWide) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: trackInfo),
                const SizedBox(width: 12),
                transportButtons,
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (favoriteButton != null) favoriteButton,
                      const SizedBox(width: 10),
                      Icon(Icons.volume_up_rounded, size: 16, color: colors.textColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      volume,
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            waveformRow,
          ],
        );
      }

      // Phone-width: track info full-width on top, then the waveform, then
      // the transport buttons centered underneath. The volume slider is
      // dropped — a phone already has hardware volume buttons.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [Expanded(child: trackInfo), if (favoriteButton != null) favoriteButton]),
          const SizedBox(height: 10),
          waveformRow,
          const SizedBox(height: 10),
          Center(child: transportButtons),
        ],
      );
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color fill;
  final Color iconColor;
  final double size;
  final VoidCallback? onPressed;

  const _RoundButton({
    required this.icon,
    required this.fill,
    this.iconColor = Colors.black,
    this.size = 34,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CartoonButton(
      circular: true,
      fill: onPressed == null ? fill.withValues(alpha: 0.4) : fill,
      padding: EdgeInsets.all(size * 0.24),
      onPressed: onPressed,
      child: Icon(icon, color: iconColor, size: size * 0.5),
    );
  }
}
