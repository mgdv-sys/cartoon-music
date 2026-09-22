import 'package:flutter/material.dart';

/// Purely decorative dancing-bars equalizer. Animates while [isPlaying],
/// flat when paused — not driven by real audio analysis.
class EqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final List<Color> colors;
  final double height;
  final double barWidth;

  const EqualizerBars({
    super.key,
    required this.isPlaying,
    required this.colors,
    this.height = 24,
    this.barWidth = 4,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.colors.length.clamp(3, 6), (i) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + (i * 90) % 300),
      )..repeat(reverse: true);
      return controller;
    });
    if (!widget.isPlaying) {
      for (final c in _controllers) {
        c.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      for (final c in _controllers) {
        widget.isPlaying ? c.repeat(reverse: true) : c.stop();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_controllers.length, (i) {
          final color = widget.colors[i % widget.colors.length];
          return Padding(
            padding: EdgeInsets.only(right: i == _controllers.length - 1 ? 0 : 3),
            child: AnimatedBuilder(
              animation: _controllers[i],
              builder: (context, child) {
                final minH = widget.height * 0.25;
                final h = widget.isPlaying
                    ? minH + (_controllers[i].value * (widget.height - minH))
                    : minH;
                return Container(
                  width: widget.barWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(widget.barWidth / 2),
                    border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}
