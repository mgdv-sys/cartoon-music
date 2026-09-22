import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/cartoon_style.dart';

/// Small "vX.Y.Z+N" label so it's always clear which build is running.
class VersionLabel extends StatelessWidget {
  final Color color;
  const VersionLabel({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null ? '' : 'v${info.version}+${info.buildNumber}';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text, style: CartoonStyle.body(color.withValues(alpha: 0.5), size: 10)),
        );
      },
    );
  }
}
