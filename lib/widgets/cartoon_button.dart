import 'package:flutter/material.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

/// A bouncy, outlined "sticker" button: springs up + rotates slightly on
/// hover, squishes down on press.
class CartoonButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Color fill;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool circular;

  const CartoonButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.fill,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.radius = CartoonStyle.radiusChip,
    this.circular = false,
  });

  @override
  State<CartoonButton> createState() => _CartoonButtonState();
}

class _CartoonButtonState extends State<CartoonButton> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressing
        ? CartoonStyle.pressScale
        : (_hovering ? CartoonStyle.hoverScale : 1.0);
    final rotate = _hovering && !_pressing ? CartoonStyle.hoverRotateRadians : 0.0;
    final translateY = _hovering && !_pressing ? CartoonStyle.hoverTranslateY : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        // Only register tap handling when there's actually a callback —
        // otherwise this always-on GestureDetector (even with onTap null)
        // still wins the tap-gesture arena over an ancestor that wraps this
        // button to make it tappable itself (e.g. a PopupMenuButton using a
        // disabled CartoonButton purely as its decorative label), silently
        // swallowing the tap and never letting the ancestor's own handler
        // fire.
        onTapDown: widget.onPressed == null ? null : (_) => setState(() => _pressing = true),
        onTapUp: widget.onPressed == null ? null : (_) => setState(() => _pressing = false),
        onTapCancel: widget.onPressed == null ? null : () => setState(() => _pressing = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: CartoonStyle.springDuration,
          curve: CartoonStyle.springCurve,
          transform: Matrix4.identity()
            ..translateByDouble(0.0, translateY, 0.0, 1.0)
            ..scaleByDouble(scale, scale, scale, 1.0)
            ..rotateZ(rotate),
          transformAlignment: Alignment.center,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.fill,
            shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circular ? null : BorderRadius.circular(widget.radius),
            border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThick),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
