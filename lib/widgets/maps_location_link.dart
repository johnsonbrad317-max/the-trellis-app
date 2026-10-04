import 'package:flutter/material.dart';

import '../services/maps_launcher.dart';
import '../theme/app_colors.dart';
import 'bookplate_dialog.dart';
import 'brass_glyph.dart';

/// A meeting location rendered as a tappable link: a brass pin and the
/// address in underlined brass lettering. Tapping anywhere on the row opens
/// the address in the platform's maps app (Apple Maps on iOS, Google Maps
/// elsewhere). The row is at least 44px tall to meet touch-target guidance.
class MapsLocationLink extends StatelessWidget {
  const MapsLocationLink(this.address, {super.key, this.style});

  final String address;

  /// Overrides the address lettering; defaults to the theme's body style.
  /// Colour and underline are always applied on top.
  final TextStyle? style;

  Future<void> _open(BuildContext context) async {
    final opened = await openAddressInMaps(address);
    if (!opened && context.mounted) {
      showBookplateNotice(context, "Couldn't open Maps for that address.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;

    return Semantics(
      button: true,
      label: 'Open $address in Maps',
      onTap: () => _open(context),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              const BrassGlyph(BrassGlyphKind.pin, size: 18, color: AppColors.antiqueBrass),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  address,
                  style: base?.copyWith(
                    color: AppColors.antiqueBrass,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.antiqueBrass,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
