import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../library/artwork_store.dart';
import '../library/metadata_lookup_service.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../widgets/cartoon_button.dart';
import '../widgets/playback_scaffold.dart';

/// Lets the user hand-edit a track's title/artist/album/track number/genre/
/// year, with an "Autofill" action that looks the song up on MusicBrainz and
/// offers matches to fill the form from. Also the entry point for deleting
/// the song entirely (DB row + the actual file on disk).
class EditTrackScreen extends StatefulWidget {
  final LibraryTrack track;
  const EditTrackScreen({super.key, required this.track});

  @override
  State<EditTrackScreen> createState() => _EditTrackScreenState();
}

class _EditTrackScreenState extends State<EditTrackScreen> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _trackNumber;
  late final TextEditingController _genre;
  late final TextEditingController _year;

  bool _saving = false;
  bool _lookingUp = false;
  List<MetadataMatch> _matches = [];
  bool _searched = false;

  bool _fetchingArt = false;
  String? _fetchedArtworkPath;
  bool _artFetchFailed = false;

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    _title = TextEditingController(text: t.title);
    _artist = TextEditingController(text: t.artist);
    _album = TextEditingController(text: t.album);
    _trackNumber = TextEditingController(text: t.trackNumber == 0 ? '' : '${t.trackNumber}');
    _genre = TextEditingController(text: t.genre ?? '');
    _year = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _trackNumber.dispose();
    _genre.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _autofill() async {
    setState(() {
      _lookingUp = true;
      _searched = true;
      _matches = [];
    });
    final results = await MetadataLookupService.search(
      title: _title.text.trim().isNotEmpty ? _title.text.trim() : widget.track.title,
      artist: _artist.text.trim(),
      localDuration: widget.track.duration,
    );
    if (!mounted) return;
    setState(() {
      _matches = results;
      _lookingUp = false;
    });
    if (results.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No online matches found for this song.')),
      );
    }
  }

  void _applyMatch(MetadataMatch match) {
    setState(() {
      _title.text = match.title;
      _artist.text = match.artist;
      if (match.album.isNotEmpty) _album.text = match.album;
      if (match.releaseYear != null) _year.text = '${match.releaseYear}';
      if (match.genre != null && match.genre!.isNotEmpty) _genre.text = match.genre!;
      _matches = [];
      _artFetchFailed = false;
    });
    if (match.releaseId != null && match.album.isNotEmpty) {
      _fetchArt(releaseId: match.releaseId!, artist: match.artist, album: match.album);
    }
  }

  Future<void> _fetchArt({required String releaseId, required String artist, required String album}) async {
    setState(() => _fetchingArt = true);
    final path = await MetadataLookupService.fetchAndSaveCoverArt(
      releaseId: releaseId,
      artist: artist,
      album: album,
    );
    if (!mounted) return;
    setState(() {
      _fetchingArt = false;
      if (path != null) {
        _fetchedArtworkPath = path;
      } else {
        _artFetchFailed = true;
      }
    });
  }

  Future<void> _pickCoverFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose cover art',
    );
    final picked = result?.files.single;
    if (picked?.path == null) return;

    setState(() {
      _fetchingArt = true;
      _artFetchFailed = false;
    });
    try {
      final file = File(picked!.path!);
      final ext = picked.extension?.toLowerCase() ?? 'jpg';
      final saved = await ArtworkStore.saveBytes(
        await file.readAsBytes(),
        artist: _artist.text.trim().isNotEmpty ? _artist.text.trim() : widget.track.artist,
        album: _album.text.trim().isNotEmpty ? _album.text.trim() : widget.track.album,
        ext: ext,
      );
      if (!mounted) return;
      setState(() {
        _fetchedArtworkPath = saved;
        _fetchingArt = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _fetchingArt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not use that image.')),
      );
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _artist.text.trim().isEmpty || _album.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title, artist, and album can\'t be empty.')),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<AppState>().updateTrackMetadata(
          widget.track,
          title: _title.text.trim(),
          artist: _artist.text.trim(),
          album: _album.text.trim(),
          trackNumber: int.tryParse(_trackNumber.text.trim()) ?? 0,
          genre: _genre.text.trim().isEmpty ? null : _genre.text.trim(),
          releaseYear: int.tryParse(_year.text.trim()),
          artworkPath: _fetchedArtworkPath,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;

    return PlaybackScaffold(
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text('Edit song', style: CartoonStyle.heading(colors.textColor, size: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _artworkPreview(),
              const SizedBox(width: 16),
              Expanded(
                child: CartoonButton(
                  fill: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  onPressed: _lookingUp ? null : _autofill,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _lookingUp
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Autofill from online lookup',
                          style: CartoonStyle.body(Colors.black, size: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_searched && !_lookingUp && _matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Pick a match (best first):',
              style: CartoonStyle.body(colors.textColor.withValues(alpha: 0.7), size: 12),
            ),
            const SizedBox(height: 6),
            ..._matches.map((m) => _MatchCard(
                  match: m,
                  localDuration: widget.track.duration,
                  onTap: () => _applyMatch(m),
                )),
          ],
          const SizedBox(height: 20),
          _field('Title', _title),
          const SizedBox(height: 12),
          _field('Artist', _artist),
          const SizedBox(height: 12),
          _field('Album', _album),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field('Track #', _trackNumber, keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field('Year', _year, keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 12),
          _field('Genre', _genre),
          const SizedBox(height: 24),
          CartoonButton(
            fill: colors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            onPressed: _saving ? null : _save,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Save', style: CartoonStyle.body(Colors.white, size: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artworkPreview() {
    final path = _fetchedArtworkPath ?? widget.track.artworkPath;
    return GestureDetector(
      onTap: _fetchingArt ? null : _pickCoverFromFile,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black26),
              image: path != null ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover) : null,
            ),
            child: Stack(
              children: [
                if (path == null) const Center(child: Icon(Icons.album_rounded, color: Colors.black38, size: 28)),
                if (_fetchingArt)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_fetchedArtworkPath != null)
            const Text('New cover', style: TextStyle(fontSize: 10, color: Colors.green))
          else if (_artFetchFailed)
            const Text('No cover found — tap to pick', style: TextStyle(fontSize: 10, color: Colors.black45))
          else
            const Text('Tap to change', style: TextStyle(fontSize: 10, color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}

/// One autofill candidate: title/artist/album/year plus a match-confidence
/// badge and a "closest length" cue when its duration nearly matches the
/// local file's — the two things that actually help tell several
/// similarly-named results apart, instead of a single flat line of text.
class _MatchCard extends StatelessWidget {
  final MetadataMatch match;
  final Duration localDuration;
  final VoidCallback onTap;

  const _MatchCard({required this.match, required this.localDuration, required this.onTap});

  bool get _isCloseLength =>
      match.duration != null && (match.duration! - localDuration).abs() <= const Duration(seconds: 3);

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      match.artist,
      if (match.album.isNotEmpty) match.album else 'Unknown album',
      if (match.releaseYear != null) '${match.releaseYear}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(match.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitleParts.join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (match.score > 0) _Badge(text: '${match.score}% match', color: Colors.blue),
                  if (match.duration != null) _Badge(text: _fmtDuration(match.duration!), color: Colors.black45),
                  if (_isCloseLength) _Badge(text: 'Closest length', color: Colors.green),
                ],
              ),
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
