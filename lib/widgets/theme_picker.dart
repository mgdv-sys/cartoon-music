import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'theme_editor.dart';

const _builtInPalettes = [
  CartoonPalette.sunny,
  CartoonPalette.bubblegum,
  CartoonPalette.mintSoda,
  CartoonPalette.grapePop,
  CartoonPalette.oceanBreeze,
  CartoonPalette.darkCartoon,
];

/// A swatch row that recolors the whole app when tapped, plus a "Custom"
/// entry that opens the full theme editor (colors + background image).
class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: CartoonStyle.heading(app.colors.textColor, size: 18)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final p in _builtInPalettes)
                  _Swatch(
                    color: kPalettes[p]!.accent,
                    label: kPalettes[p]!.displayName,
                    selected: app.palette == p,
                    textColor: app.colors.textColor,
                    onTap: () => app.setPalette(p),
                  ),
                _Swatch(
                  color: app.customTheme.accent ?? app.colors.accent,
                  label: 'Custom',
                  selected: app.palette == CartoonPalette.custom,
                  textColor: app.colors.textColor,
                  icon: Icons.edit_rounded,
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ThemeEditorSheet(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final Color textColor;
  final VoidCallback onTap;
  final IconData? icon;

  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.textColor,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: kOutlineColor,
                width: selected ? CartoonStyle.outlineThick : CartoonStyle.outlineThin,
              ),
            ),
            child: Icon(
              icon ?? (selected ? Icons.check_rounded : null),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: CartoonStyle.body(textColor, size: 11)),
        ],
      ),
    );
  }
}
