import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// The app's logo: the flask on its light ground as a rounded square [size]
/// wide, cropped the way the launcher icon is. The ground is part of the
/// image, which is what lets the dark outline read on a dark screen too.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  /// The image has wide margins; this share of it is shown (the launcher
  /// icon's crop).
  static const _share = 0.8624;

  @override
  Widget build(BuildContext context) {
    final drawn = size / _share;
    return Semantics(
      image: true,
      label: '$appName logo',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: OverflowBox(
              maxWidth: drawn,
              maxHeight: drawn,
              child: Image.asset(
                appLogoAsset,
                width: drawn,
                height: drawn,
                // Decoded no larger than any screen needs.
                cacheWidth: 600,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
