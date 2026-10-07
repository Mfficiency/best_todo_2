import 'package:flutter/material.dart';

/// Best Music's app icon (the motion-blurred note — same artwork as the
/// launcher icon in android/app/src/music/res) as a rounded tile, for the
/// drawer header and the About page.
class BestMusicLogo extends StatelessWidget {
  const BestMusicLogo({super.key, this.size = 48});

  static const String assetPath = 'assets/branding/best_music_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Best Music',
      ),
    );
  }
}
