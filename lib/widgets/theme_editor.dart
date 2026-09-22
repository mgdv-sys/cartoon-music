import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/cartoon_style.dart';
import '../theme/palettes.dart';

const List<Color> _presetSwatches = [
  Color(0xFFFBE5C8), Color(0xFFF2C14E), Color(0xFFE2483D), Color(0xFF37A66B),
  Color(0xFF5BC4F2), Color(0xFFB58BE0), Color(0xFFF2843D), Color(0xFFFCE0E8),
  Color(0xFFF7B8D0), Color(0xFFE85D9B), Color(0xFF9B7BF5), Color(0xFFDCEFE4),
  Color(0xFFA8DCC2), Color(0xFF2BA877), Color(0xFFE4E0F5), Color(0xFFC4BAEC),
  Color(0xFF7A5BD6), Color(0xFFD6ECF5), Color(0xFFA5D6EC), Color(0xFF2E8BC4),
  Color(0xFF2A2630), Color(0xFF34303C), Color(0xFFFF5E5B), Color(0xFF1A1A1A),
  Color(0xFFFFFFFF), Color(0xFFF0EDE6), Color(0xFF4ED9A4), Color(0xFFC08BF0),
];

/// Full custom-theme editor: pick a background image (or clear it), and
/// pick arbitrary colors (hex entry + quick swatches) for background,
/// sidebar, accent, and text.
class ThemeEditorSheet extends StatefulWidget {
  const ThemeEditorSheet({super.key});

  @override
  State<ThemeEditorSheet> createState() => _ThemeEditorSheetState();
}

class _ThemeEditorSheetState extends State<ThemeEditorSheet> {
  late CustomThemeConfig _draft;

  @override
  void initState() {
    super.initState();
    _draft = context.read<AppState>().customTheme;
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose a background image',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _draft = _draft.copyWith(backgroundImagePath: path));
  }

  void _apply() {
    final app = context.read<AppState>();
    app.setCustomTheme(_draft);
    app.setPalette(CartoonPalette.custom);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _draft.toPaletteColors();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Customize theme', style: CartoonStyle.heading(preview.textColor, size: 18)),
              const SizedBox(height: 16),
              Text('Background image', style: CartoonStyle.body(preview.textColor, size: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_rounded),
                      label: Text(_draft.backgroundImagePath == null ? 'Choose image' : 'Change image'),
                    ),
                  ),
                  if (_draft.backgroundImagePath != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _draft = _draft.copyWith(clearImage: true)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              _ColorField(
                label: 'Background color',
                value: _draft.background ?? preview.background,
                onChanged: (c) => setState(() => _draft = _draft.copyWith(background: c)),
              ),
              _ColorField(
                label: 'Sidebar / top bar color',
                value: _draft.sidebar ?? preview.sidebar,
                onChanged: (c) => setState(() => _draft = _draft.copyWith(sidebar: c)),
              ),
              _ColorField(
                label: 'Accent color',
                value: _draft.accent ?? preview.accent,
                onChanged: (c) => setState(() => _draft = _draft.copyWith(accent: c)),
              ),
              _ColorField(
                label: 'Text color',
                value: _draft.textColor ?? preview.textColor,
                onChanged: (c) => setState(() => _draft = _draft.copyWith(textColor: c)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _apply();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply custom theme'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorField extends StatelessWidget {
  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;
  const _ColorField({required this.label, required this.value, required this.onChanged});

  Future<void> _openPicker(BuildContext context) async {
    final controller = TextEditingController(
      text: '#${value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
    );
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Hex color (e.g. #FF6B4A)'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetSwatches
                    .map((c) => GestureDetector(
                          onTap: () => Navigator.of(context).pop(c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: kOutlineColor, width: 1.5),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final parsed = _parseHex(controller.text);
              Navigator.of(context).pop(parsed);
            },
            child: const Text('Use hex'),
          ),
        ],
      ),
    );
    if (picked != null) onChanged(picked);
  }

  Color? _parseHex(String input) {
    var hex = input.trim().replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => _openPicker(context),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value,
                shape: BoxShape.circle,
                border: Border.all(color: kOutlineColor, width: 2),
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: CartoonStyle.body(Colors.black87, size: 14)),
          ],
        ),
      ),
    );
  }
}
