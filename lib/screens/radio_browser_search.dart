import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../library/radio_browser_service.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

/// Search screen for the Radio Browser directory (radio-browser.info) — a
/// free, community-maintained database of real internet radio stations
/// worldwide. Lets the user search by name and/or country and add results
/// straight into their saved Radio stations.
class RadioBrowserSearchScreen extends StatefulWidget {
  const RadioBrowserSearchScreen({super.key});

  @override
  State<RadioBrowserSearchScreen> createState() => _RadioBrowserSearchScreenState();
}

class _RadioBrowserSearchScreenState extends State<RadioBrowserSearchScreen> {
  final _nameController = TextEditingController();
  final _countryController = TextEditingController(text: 'Philippines');
  List<RadioBrowserResult>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await RadioBrowserService.search(
        name: _nameController.text,
        country: _countryController.text,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final colors = app.colors;
    final savedUrls = app.radioStations.map((s) => s.url).toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text('Browse stations', style: CartoonStyle.heading(colors.textColor, size: 20)),
        backgroundColor: colors.background,
        foregroundColor: colors.textColor,
        elevation: 0,
      ),
      backgroundColor: colors.background,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(hintText: 'Station name (optional)', prefixIcon: Icon(Icons.search_rounded)),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _countryController,
                  decoration: const InputDecoration(hintText: 'Country', prefixIcon: Icon(Icons.public_rounded)),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _loading ? null : _search, child: const Text('Search')),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(colors, savedUrls, app)),
        ],
      ),
    );
  }

  Widget _buildBody(PaletteColors colors, Set<String> savedUrls, AppState app) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: CartoonStyle.body(colors.textColor)),
        ),
      );
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return Center(
        child: Text('No stations found.', style: CartoonStyle.body(colors.textColor)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final station = results[index];
        final alreadySaved = savedUrls.contains(station.url);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(CartoonStyle.radiusCard),
              border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kOutlineColor, width: CartoonStyle.outlineThin),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: station.favicon != null
                      ? Image.network(
                          station.favicon!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.radio_rounded, color: Colors.white),
                        )
                      : const Icon(Icons.radio_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: CartoonStyle.body(Colors.black, size: 14).copyWith(fontWeight: FontWeight.w600)),
                      if (station.subtitle.isNotEmpty)
                        Text(station.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: CartoonStyle.body(Colors.black54, size: 12)),
                    ],
                  ),
                ),
                if (alreadySaved)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.check_circle_rounded, color: Colors.green),
                  )
                else
                  TextButton(
                    onPressed: () async {
                      await app.addRadioStation(station.name, station.url, logoUrl: station.favicon);
                      if (context.mounted) setState(() {});
                    },
                    child: const Text('Add'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
