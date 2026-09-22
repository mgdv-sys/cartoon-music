import 'package:flutter/material.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'cartoon_button.dart';

/// Top bar: back/forward round buttons, chunky search pill, history +
/// account avatar.
class TopBar extends StatelessWidget {
  final PaletteColors colors;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onAvatarTap;

  const TopBar({
    super.key,
    required this.colors,
    this.onSearchChanged,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
      ),
      child: Row(
        children: [
          CartoonButton(
            circular: true,
            fill: Colors.white,
            padding: const EdgeInsets.all(8),
            onPressed: () {},
            child: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
          const SizedBox(width: 8),
          CartoonButton(
            circular: true,
            fill: Colors.white,
            padding: const EdgeInsets.all(8),
            onPressed: () {},
            child: const Icon(Icons.arrow_forward_rounded, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(CartoonStyle.radiusChip),
                border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: kOutlineColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: onSearchChanged,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search songs, albums, artists, podcasts',
                        isDense: true,
                      ),
                      style: CartoonStyle.body(Colors.black, size: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          CartoonButton(
            circular: true,
            fill: Colors.white,
            padding: const EdgeInsets.all(8),
            onPressed: () {},
            child: const Icon(Icons.history_rounded, size: 18),
          ),
          const SizedBox(width: 8),
          CartoonButton(
            circular: true,
            fill: colors.accent,
            padding: const EdgeInsets.all(8),
            onPressed: onAvatarTap,
            child: const Icon(Icons.person_rounded, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
