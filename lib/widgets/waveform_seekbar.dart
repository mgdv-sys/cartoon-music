import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/palettes.dart';

/// A decorative "waveform" scrubber: the played portion renders as a row of
/// colorful bars with randomized (but stable per-track) heights, the
/// unplayed portion as a row of small square outline dots — tap or drag
/// anywhere to seek. Not driven by real audio analysis, just a stylized
/// stand-in for one, seeded per track so it doesn't reshuffle every frame.
/// While [isPlaying], the played bars gently bob up and down like a
/// spectrum analyzer (a continuous sine sweep, staggered per bar) — the
/// same decorative-animation idea as [EqualizerBars], just applied here too.
class WaveformSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final List<Color> barColors;
  final ValueChanged<Duration> onSeek;
  final int seed;
  final double height;
  final Color dotColor;
  final bool isPlaying;

  const WaveformSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.barColors,
    required this.onSeek,
    this.seed = 0,
    this.height = 28,
    this.dotColor = kOutlineColor,
    this.isPlaying = false,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      widget.isPlaying ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handle(Offset localPosition, double width) {
    if (widget.duration == Duration.zero) return;
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek(widget.duration * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds == 0
        ? 0.0
        : (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      const pitch = 6.0; // spacing between bar/dot centers
      final count = max(1, (width / pitch).floor());
      final playedCount = (count * progress).round();
      final random = Random(widget.seed);
      final barHeights = List.generate(count, (_) => 0.3 + random.nextDouble() * 0.7);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _handle(d.localPosition, width),
        onHorizontalDragUpdate: (d) => _handle(d.localPosition, width),
        child: SizedBox(
          height: widget.height,
          width: width,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final phase = _controller.value * 2 * pi;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(count, (i) {
                  final played = i < playedCount;
                  if (played) {
                    final color = widget.barColors.isEmpty ? widget.dotColor : widget.barColors[i % widget.barColors.length];
                    final wobble = widget.isPlaying ? 0.7 + 0.3 * sin(phase + i * 0.8) : 1.0;
                    return Container(
                      width: 2.5,
                      height: (widget.height * barHeights[i] * wobble).clamp(4.0, widget.height),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    );
                  }
                  return Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: widget.dotColor.withValues(alpha: 0.5), width: 1),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      );
    });
  }
}
