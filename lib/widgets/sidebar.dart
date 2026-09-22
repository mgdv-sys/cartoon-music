import 'package:flutter/material.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import 'cartoon_button.dart';
import 'version_label.dart';

enum NavSection { home, playlists, artists, mostPlayed, recentlyPlayed, favorites, allTracks, radio }

const Map<NavSection, String> kNavLabels = {
  NavSection.home: 'Home',
  NavSection.playlists: 'Playlists',
  NavSection.artists: 'Artists',
  NavSection.mostPlayed: 'Most Played',
  NavSection.recentlyPlayed: 'Recently Played',
  NavSection.favorites: 'Favorites',
  NavSection.allTracks: 'All Tracks',
  NavSection.radio: 'Radio',
};

const Map<NavSection, IconData> kNavIcons = {
  NavSection.home: Icons.home_rounded,
  NavSection.playlists: Icons.queue_music_rounded,
  NavSection.artists: Icons.person_rounded,
  NavSection.mostPlayed: Icons.local_fire_department_rounded,
  NavSection.recentlyPlayed: Icons.history_rounded,
  NavSection.favorites: Icons.favorite_rounded,
  NavSection.allTracks: Icons.library_music_rounded,
  NavSection.radio: Icons.radio_rounded,
};

/// Desktop-only left sidebar (~210px): logo, nav pills, and "+ New playlist".
/// Playlists themselves are only listed on the Playlists page (via the nav
/// pill above), not duplicated here.
class Sidebar extends StatelessWidget {
  final PaletteColors colors;
  final NavSection current;
  final void Function(NavSection) onSelect;
  final VoidCallback onNewPlaylist;

  const Sidebar({
    super.key,
    required this.colors,
    required this.current,
    required this.onSelect,
    required this.onNewPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: kOutlineColor, width: CartoonStyle.outlineThick)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Text('Playah', style: CartoonStyle.heading(colors.textColor, size: 16)),
              ],
            ),
          ),
          for (final section in NavSection.values)
            _NavPill(
              label: kNavLabels[section]!,
              icon: kNavIcons[section]!,
              active: current == section,
              colors: colors,
              onTap: () => onSelect(section),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: CartoonButton(
              fill: Colors.white,
              onPressed: onNewPlaylist,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text('New playlist', style: CartoonStyle.body(Colors.black, size: 13)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Center(child: VersionLabel(color: colors.textColor)),
        ],
      ),
    );
  }
}

class _NavPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final PaletteColors colors;
  final VoidCallback onTap;

  const _NavPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_NavPill> createState() => _NavPillState();
}

class _NavPillState extends State<_NavPill> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: CartoonStyle.springDuration,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.active
                  ? widget.colors.accent
                  : (_hovering ? Colors.white.withValues(alpha: 0.35) : Colors.transparent),
              borderRadius: BorderRadius.circular(CartoonStyle.radiusChip),
              border: widget.active ? Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin) : null,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: widget.active ? Colors.white : widget.colors.textColor),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: CartoonStyle.body(
                    widget.active ? Colors.white : widget.colors.textColor,
                    size: 14,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
