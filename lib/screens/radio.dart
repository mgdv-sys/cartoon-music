import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show webViewAvailable;
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';
import '../widgets/cartoon_button.dart';
import 'radio_browser_search.dart';
import 'web_player.dart';

/// Hosts whose links should be treated as [RadioStationType.web] (opened in
/// the embedded web player) rather than [RadioStationType.audio] (a direct
/// stream URL played through just_audio) by default when adding a station.
const _webLinkHosts = ['youtube.com', 'youtu.be', 'twitch.tv', 'soundcloud.com'];

bool _looksLikeWebLink(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return _webLinkHosts.any((h) => host == h || host.endsWith('.$h'));
}

/// Best-effort logo for a manually-added station: no favicon is supplied by
/// hand, so this asks a favicon-lookup service for the station's own site
/// icon (its real branding, not a stock substitute). `_StationTile` falls
/// back to a plain icon if this 404s or the host has none.
String? _guessLogoUrl(String url) {
  final host = Uri.tryParse(url)?.host;
  if (host == null || host.isEmpty) return null;
  return 'https://www.google.com/s2/favicons?sz=128&domain=$host';
}

/// Radio screen: saved internet radio stations (name + stream URL), with a
/// way to add new ones and play them straight away — no local file needed.
class RadioScreen extends StatelessWidget {
  const RadioScreen({super.key});

  Future<void> _addStation(BuildContext context) async {
    final app = context.read<AppState>();
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    RadioStationType type = RadioStationType.audio;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add station or link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: webViewAvailable ? 'Stream or link URL (https://...)' : 'Stream URL (https://...)',
                ),
                keyboardType: TextInputType.url,
                onChanged: webViewAvailable
                    ? (value) => setState(() => type = _looksLikeWebLink(value) ? RadioStationType.web : RadioStationType.audio)
                    : null,
              ),
              if (webViewAvailable) ...[
                const SizedBox(height: 12),
                SegmentedButton<RadioStationType>(
                  segments: const [
                    ButtonSegment(value: RadioStationType.audio, label: Text('Radio stream'), icon: Icon(Icons.radio_rounded)),
                    ButtonSegment(value: RadioStationType.web, label: Text('Web link'), icon: Icon(Icons.smart_display_rounded)),
                  ],
                  selected: {type},
                  onSelectionChanged: (selection) => setState(() => type = selection.first),
                ),
                const SizedBox(height: 4),
                Text(
                  type == RadioStationType.web
                      ? 'Opens in an embedded web player (YouTube, Twitch, etc.)'
                      : 'Played directly as an audio stream',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ] else ...[
                const SizedBox(height: 8),
                const Text(
                  'Web links (YouTube, Twitch, etc.) aren\'t available on Linux desktop yet — only direct audio stream URLs.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameController.text.trim();
    final url = urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    await app.addRadioStation(name, url, type: type, logoUrl: _guessLogoUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Radio', style: CartoonStyle.heading(colors.textColor, size: 28)),
              const Spacer(),
              CartoonButton(
                fill: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RadioBrowserSearchScreen(),
                )),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore_rounded, color: colors.accent, size: 18),
                    const SizedBox(width: 6),
                    Text('Browse', style: CartoonStyle.body(colors.accent, size: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CartoonButton(
                fill: colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                onPressed: () => _addStation(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text('Add', style: CartoonStyle.body(Colors.white, size: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Live streams and saved links, ready to play any time.',
            style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.65), size: 13),
          ),
          const SizedBox(height: 20),
          if (app.radioStations.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: CartoonStyle.stickerDecoration(fill: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No stations yet', style: CartoonStyle.heading(Colors.black)),
                  const SizedBox(height: 8),
                  Text(
                    'Add a station\'s stream URL, or a YouTube/Twitch link, to save it here and play it any time.',
                    style: CartoonStyle.body(Colors.black87),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: app.radioStations.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 380,
                mainAxisExtent: 86,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemBuilder: (context, index) => _StationTile(station: app.radioStations[index], app: app),
            ),
        ],
      ),
    );
  }
}

class _StationTile extends StatefulWidget {
  final RadioStation station;
  final AppState app;
  const _StationTile({required this.station, required this.app});

  @override
  State<_StationTile> createState() => _StationTileState();
}

class _StationTileState extends State<_StationTile> {
  bool _hovering = false;

  RadioStation get station => widget.station;
  AppState get app => widget.app;

  void _openAsWeb(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebPlayerScreen(title: station.name, url: station.url),
    ));
  }

  Future<void> _play(BuildContext context) async {
    try {
      await app.playRadioStation(station);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${station.name}" isn\'t a playable audio stream.'),
      ));
    }
  }

  void _tapUnavailableWeb(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${station.name}" is a web link — only available on Android, not Linux desktop.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = app.colors;
    final isWeb = station.type == RadioStationType.web;
    final isUnavailable = isWeb && !webViewAvailable;
    final isPlaying = !isWeb && app.currentRadioStation?.id == station.id;
    final isReconnecting = isPlaying && app.radioReconnecting;

    final String statusLabel = isUnavailable
        ? 'Android only'
        : isReconnecting
            ? 'Reconnecting…'
            : (isWeb ? 'Web link' : 'Audio stream');
    final Color statusColor = isUnavailable
        ? Colors.black38
        : isReconnecting
            ? colors.accent
            : Colors.black45;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () {
          if (isUnavailable) {
            _tapUnavailableWeb(context);
          } else if (isWeb) {
            _openAsWeb(context);
          } else {
            _play(context);
          }
        },
        child: Opacity(
          opacity: isUnavailable ? 0.5 : 1,
          child: AnimatedContainer(
            duration: CartoonStyle.springDuration,
            curve: CartoonStyle.springCurve,
            transform: Matrix4.identity()
              ..translateByDouble(0.0, !isUnavailable && _hovering ? CartoonStyle.hoverTranslateY : 0.0, 0.0, 1.0),
            transformAlignment: Alignment.center,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isPlaying ? colors.accent.withValues(alpha: 0.14) : Colors.white,
              borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
              border: Border.all(
                color: isPlaying || _hovering ? colors.accent : kOutlineColor,
                width: isPlaying ? CartoonStyle.outlineThick : CartoonStyle.outlineThin,
              ),
              boxShadow: _hovering && !isUnavailable
                  ? [BoxShadow(color: kOutlineColor.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: station.logoUrl != null
                          ? Image.network(
                              station.logoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(
                                isWeb ? Icons.smart_display_rounded : Icons.radio_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            )
                          : Icon(
                              isWeb ? Icons.smart_display_rounded : Icons.radio_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                    if (isPlaying)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isReconnecting ? Colors.black45 : colors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: isReconnecting
                              ? const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.equalizer_rounded, color: Colors.white, size: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: CartoonStyle.body(Colors.black, size: 14).copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CartoonStyle.body(statusColor, size: 12).copyWith(
                          fontWeight: isReconnecting ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Colors.black26),
                  onPressed: () => app.deleteRadioStation(station.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
