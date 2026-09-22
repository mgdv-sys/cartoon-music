import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

/// Outlined rounded artwork tile card used across shelves/grids — square
/// for albums/playlists, circular for artists. Lifts + tilts on hover.
class AlbumCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String artworkUrl;
  final bool isCircular;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final double size;
  final bool isPlaying;
  final Color? accentColor;

  const AlbumCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    this.isCircular = false,
    this.onTap,
    this.onPlay,
    this.size = 150,
    this.isPlaying = false,
    this.accentColor,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? kOutlineColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: CartoonStyle.springDuration,
          curve: CartoonStyle.springCurve,
          width: widget.size,
          transform: Matrix4.identity()
            ..translateByDouble(0.0, _hovering ? CartoonStyle.hoverTranslateY : 0.0, 0.0, 1.0)
            ..rotateZ(_hovering ? CartoonStyle.hoverRotateRadians : 0.0),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: widget.isCircular ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: widget.isCircular ? null : BorderRadius.circular(CartoonStyle.radiusCard),
                      border: Border.all(
                        color: widget.isPlaying ? (widget.accentColor ?? kOutlineColor) : kOutlineColor,
                        width: widget.isPlaying ? CartoonStyle.outlineThick + 1.5 : CartoonStyle.outlineThick,
                      ),
                      image: widget.artworkUrl.isNotEmpty
                          ? DecorationImage(image: FileImage(File(widget.artworkUrl)), fit: BoxFit.cover)
                          : null,
                    ),
                    child: widget.artworkUrl.isEmpty
                        ? const Icon(Icons.music_note_rounded, size: 40, color: kOutlineColor)
                        : null,
                  ),
                  if (widget.isPlaying)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: widget.accentColor ?? kOutlineColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: kOutlineColor, width: 1.5),
                        ),
                        child: const Icon(Icons.equalizer_rounded, color: Colors.white, size: 16),
                      ),
                    )
                  else if (widget.onPlay != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: GestureDetector(
                        onTap: widget.onPlay,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: widget.accentColor ?? kOutlineColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: kOutlineColor, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CartoonStyle.heading(textColor, size: 14),
              ),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CartoonStyle.body(textColor.withValues(alpha: 0.65), size: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
