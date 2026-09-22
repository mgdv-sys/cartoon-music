import 'package:flutter/material.dart';
import 'palettes.dart';

/// Shared style tokens for the cartoon sticker aesthetic:
/// thick outlines, chunky radii, and springy motion curves.
class CartoonStyle {
  /// Window width at which the layout switches from mobile (drawer + mini
  /// player) to desktop (sidebar + top bar + transport bar).
  static const double desktopBreakpoint = 900;

  static const double outlineThick = 3.5;
  static const double outlineThin = 2.0;

  static const double radiusCard = 18.0;
  static const double radiusChip = 32.0;
  static const double radiusSmall = 12.0;

  static const Curve springCurve = Curves.easeOutBack;
  static const Duration springDuration = Duration(milliseconds: 220);

  static const double hoverScale = 1.06;
  static const double pressScale = 0.92;
  static const double hoverRotateRadians = -0.03; // ~-1.7deg
  static const double hoverTranslateY = -4.0;

  /// Summed-up duration of a whole list of tracks (album, playlist, All
  /// Tracks…), e.g. "1h 42m" or "6m 8s" for a shorter list.
  static String formatTotalDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${d.inSeconds % 60}s';
  }

  static TextStyle heading(Color color, {double size = 22, FontWeight weight = FontWeight.w500}) => TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: weight,
        fontSize: size,
        color: color,
      );

  static TextStyle body(Color color, {double size = 14}) => TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w400,
        fontSize: size,
        color: color,
      );

  static Border outline({double width = outlineThick}) => Border.all(
        color: kOutlineColor,
        width: width,
      );

  static BoxDecoration stickerDecoration({
    required Color fill,
    double radius = radiusCard,
    double borderWidth = outlineThick,
    List<BoxShadow>? shadows,
  }) => BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kOutlineColor, width: borderWidth),
        boxShadow: shadows,
      );

  static ThemeData themeFrom(PaletteColors p) {
    final base = p.isDark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      colorScheme: base.colorScheme.copyWith(
        primary: p.accent,
        surface: p.background,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Montserrat',
        bodyColor: p.textColor,
        displayColor: p.textColor,
      ),
      // Dropdown/⋮ menus (track actions, sort, queue) otherwise render with
      // Flutter's stock plain-white/no-outline menu shape, which clashes
      // with the thick-outline sticker look used everywhere else.
      popupMenuTheme: PopupMenuThemeData(
        color: p.isDark ? p.background : Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          side: const BorderSide(color: kOutlineColor, width: outlineThin),
        ),
        textStyle: body(p.textColor, size: 14),
      ),
    );
  }
}
