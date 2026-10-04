import 'package:flutter/material.dart';

import 'trimmed_asset.dart';

/// The illustrated glyphs used in place of Material icons in each shell's
/// BottomNavigationBar. [content] is each illustration's opaque bounding box
/// inside its transparent PNG (see [TrimmedAsset]).
enum NavGlyph {
  dashboard('assets/images/nav_dashboard.png', Size(1408, 768), Rect.fromLTRB(866, 406, 1238, 658)),
  rule('assets/images/nav_rule.png', Size(2816, 1536), Rect.fromLTRB(1700, 804, 2584, 1356)),
  prayer('assets/images/nav_prayer.png', Size(2816, 1536), Rect.fromLTRB(1794, 632, 2562, 1370)),
  connect('assets/images/nav_connect.png', Size(2816, 1536), Rect.fromLTRB(1818, 378, 2650, 1414)),
  roster('assets/images/nav_roster.png', Size(2816, 1536), Rect.fromLTRB(644, 246, 2170, 1292)),
  insights('assets/images/nav_insights.png', Size(2816, 1536), Rect.fromLTRB(962, 268, 1988, 1272)),
  treasury('assets/images/nav_treasury.png', Size(2816, 1536), Rect.fromLTRB(900, 194, 1916, 1342));

  const NavGlyph(this.asset, this.imageSize, this.content);

  final String asset;
  final Size imageSize;
  final Rect content;
}

/// A BottomNavigationBar glyph drawn from real artwork rather than a default
/// Material [Icon]. Fixed at [size] square (44 by default) so the art stays
/// prominent and legible instead of being squeezed into the bar's 24px icon
/// slot; unselected tabs are dimmed since the PNGs carry no separate
/// inactive variant.
class NavIcon extends StatelessWidget {
  const NavIcon(this.glyph, {super.key, this.selected = true});

  final NavGlyph glyph;
  final bool selected;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: selected ? 1 : 0.5,
      child: SizedBox(
        width: size,
        height: size,
        child: TrimmedAsset(
          asset: glyph.asset,
          imageSize: glyph.imageSize,
          content: glyph.content,
          width: size,
          height: size,
          cacheWidth: 700,
        ),
      ),
    );
  }
}
