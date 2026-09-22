import 'package:flutter/material.dart';
import '../theme/cartoon_style.dart';
import 'album_card.dart';
import 'cartoon_button.dart';

/// A single card's worth of display data for a shelf — domain-agnostic so
/// the same widget can show albums, tracks, or playlists.
class ShelfItem {
  final String id;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final bool isCircular;
  const ShelfItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artworkPath,
    this.isCircular = false,
  });
}

/// A titled horizontal carousel: bold title + "More" pill + left/right
/// arrow buttons that scroll the row of cards.
class ShelfWidget extends StatefulWidget {
  final String title;
  final List<ShelfItem> items;
  final Color textColor;
  final Color accent;
  final void Function(ShelfItem item)? onItemTap;

  const ShelfWidget({
    super.key,
    required this.title,
    required this.items,
    required this.textColor,
    required this.accent,
    this.onItemTap,
  });

  @override
  State<ShelfWidget> createState() => _ShelfWidgetState();
}

class _ShelfWidgetState extends State<ShelfWidget> {
  final _controller = ScrollController();

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: CartoonStyle.heading(widget.textColor, size: 24)),
            const Spacer(),
            CartoonButton(
              circular: true,
              fill: Colors.white,
              padding: const EdgeInsets.all(8),
              onPressed: () => _scrollBy(-400),
              child: const Icon(Icons.chevron_left_rounded, size: 20),
            ),
            const SizedBox(width: 6),
            CartoonButton(
              circular: true,
              fill: Colors.white,
              padding: const EdgeInsets.all(8),
              onPressed: () => _scrollBy(400),
              child: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              return AlbumCard(
                title: item.title,
                subtitle: item.subtitle,
                artworkUrl: item.artworkPath ?? '',
                isCircular: item.isCircular,
                onTap: () => widget.onItemTap?.call(item),
              );
            },
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}
