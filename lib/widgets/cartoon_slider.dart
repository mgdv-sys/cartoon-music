import 'package:flutter/material.dart';
import '../theme/palettes.dart';

/// A chunky outlined slider matching the cartoon sticker look — a thick
/// black-bordered pill track, accent fill, and a bouncy circular thumb.
/// Used for playback progress and volume instead of the plain Material
/// Slider.
class CartoonSlider extends StatelessWidget {
  final double value;
  final double max;
  final Color accent;
  final ValueChanged<double> onChanged;
  final double height;
  final double thumbSize;

  const CartoonSlider({
    super.key,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.max = 1.0,
    this.height = 14,
    this.thumbSize = 22,
  });

  void _handle(BuildContext context, Offset localPosition, double width) {
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    onChanged(fraction * max);
  }

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _handle(context, d.localPosition, width),
        onHorizontalDragUpdate: (d) => _handle(context, d.localPosition, width),
        child: SizedBox(
          height: thumbSize,
          width: width,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(color: kOutlineColor, width: 2),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction == 0 ? 0.0001 : fraction,
                  child: Container(height: height, color: accent),
                ),
              ),
              Positioned(
                left: (fraction * (width - thumbSize)).clamp(0.0, width - thumbSize),
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: kOutlineColor, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
