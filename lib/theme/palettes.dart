import 'package:flutter/material.dart';

/// The six built-in cartoon color palettes, plus a user-defined `custom`
/// theme (colors and/or a background image — see CustomThemeConfig).
enum CartoonPalette {
  sunny,
  bubblegum,
  mintSoda,
  grapePop,
  oceanBreeze,
  darkCartoon,
  custom,
}

class PaletteColors {
  final String displayName;
  final Color background;
  final Color sidebar;
  final Color accent;
  final List<Color> supportingAccents;
  final List<Color> equalizerColors;
  final Color textColor;
  final bool isDark;

  /// When set, this image is painted behind the whole app instead of the
  /// flat [background] color (custom theme only).
  final String? backgroundImagePath;

  const PaletteColors({
    required this.displayName,
    required this.background,
    required this.sidebar,
    required this.accent,
    required this.supportingAccents,
    required this.equalizerColors,
    required this.textColor,
    required this.isDark,
    this.backgroundImagePath,
  });
}

const Color kOutlineColor = Color(0xFF1A1A1A);

const List<Color> _lightEqualizer = [
  Color(0xFFE2483D),
  Color(0xFFF2843D),
  Color(0xFFF2C14E),
  Color(0xFF37A66B),
  Color(0xFF5BC4F2),
  Color(0xFFB58BE0),
];

const List<Color> _darkEqualizer = [
  Color(0xFFFF5E5B),
  Color(0xFFFFB84E),
  Color(0xFFFFE14E),
  Color(0xFF4ED9A4),
  Color(0xFF5BC4F2),
  Color(0xFFC08BF0),
];

final Map<CartoonPalette, PaletteColors> kPalettes = {
  CartoonPalette.sunny: const PaletteColors(
    displayName: 'Sunny',
    background: Color(0xFFFBE5C8),
    sidebar: Color(0xFFF2C14E),
    accent: Color(0xFFE2483D),
    supportingAccents: [
      Color(0xFF37A66B),
      Color(0xFF5BC4F2),
      Color(0xFFB58BE0),
      Color(0xFFF2843D),
    ],
    equalizerColors: _lightEqualizer,
    textColor: kOutlineColor,
    isDark: false,
  ),
  CartoonPalette.bubblegum: const PaletteColors(
    displayName: 'Bubblegum',
    background: Color(0xFFFCE0E8),
    sidebar: Color(0xFFF7B8D0),
    accent: Color(0xFFE85D9B),
    supportingAccents: [
      Color(0xFF9B7BF5),
      Color(0xFF5BC4F2),
      Color(0xFFFFC34E),
    ],
    equalizerColors: _lightEqualizer,
    textColor: kOutlineColor,
    isDark: false,
  ),
  CartoonPalette.mintSoda: const PaletteColors(
    displayName: 'Mint soda',
    background: Color(0xFFDCEFE4),
    sidebar: Color(0xFFA8DCC2),
    accent: Color(0xFF2BA877),
    supportingAccents: [
      Color(0xFF5BC4F2),
      Color(0xFFFFC34E),
      Color(0xFFF2843D),
    ],
    equalizerColors: _lightEqualizer,
    textColor: kOutlineColor,
    isDark: false,
  ),
  CartoonPalette.grapePop: const PaletteColors(
    displayName: 'Grape pop',
    background: Color(0xFFE4E0F5),
    sidebar: Color(0xFFC4BAEC),
    accent: Color(0xFF7A5BD6),
    supportingAccents: [
      Color(0xFFE85D9B),
      Color(0xFF5BC4F2),
      Color(0xFFFFC34E),
    ],
    equalizerColors: _lightEqualizer,
    textColor: kOutlineColor,
    isDark: false,
  ),
  CartoonPalette.oceanBreeze: const PaletteColors(
    displayName: 'Ocean breeze',
    background: Color(0xFFD6ECF5),
    sidebar: Color(0xFFA5D6EC),
    accent: Color(0xFF2E8BC4),
    supportingAccents: [
      Color(0xFF2BA877),
      Color(0xFFF2843D),
      Color(0xFFFFC34E),
    ],
    equalizerColors: _lightEqualizer,
    textColor: kOutlineColor,
    isDark: false,
  ),
  CartoonPalette.darkCartoon: const PaletteColors(
    displayName: 'Dark cartoon',
    background: Color(0xFF2A2630),
    sidebar: Color(0xFF34303C),
    accent: Color(0xFFFF5E5B),
    supportingAccents: [
      Color(0xFFFFB84E),
      Color(0xFF4ED9A4),
      Color(0xFF5BC4F2),
      Color(0xFFC08BF0),
    ],
    equalizerColors: _darkEqualizer,
    textColor: Color(0xFFF0EDE6),
    isDark: true,
  ),
};
