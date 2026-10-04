import 'package:flutter/material.dart';

import '../widgets/brass_glyph.dart';

/// The three roles The Trellis is built around.
enum UserRole {
  runner,
  witness,
  cloud;

  String get label => switch (this) {
        UserRole.runner => 'The Runner',
        UserRole.witness => 'The Witness',
        UserRole.cloud => 'The Cloud',
      };

  /// Short form used in tight spaces, e.g. "Begin as a $shortLabel".
  String get shortLabel => switch (this) {
        UserRole.runner => 'Runner',
        UserRole.witness => 'Witness',
        UserRole.cloud => 'Cloud',
      };

  String get tagline => switch (this) {
        UserRole.runner => 'Anchor Your Days.',
        UserRole.witness => 'Walk Alongside.',
        UserRole.cloud => 'Shepherd with Clarity.',
      };

  String get description => switch (this) {
        UserRole.runner => 'Building baseline rhythms over seasons.',
        UserRole.witness => 'Lifting the administrative burden to support holistic growth.',
        UserRole.cloud => 'Giving leaders real-time insight to shepherd their flock.',
      };

  /// Used in small/inline contexts (e.g. the role-switcher sheet's compact
  /// list rows) where a full illustration would be out of place. The big
  /// role cards use [cardArtAsset] instead — see OrnateRoleCard
  /// (lib/widgets/ornate_role_card.dart).
  BrassGlyphKind get glyph => switch (this) {
        UserRole.runner => BrassGlyphKind.person,
        UserRole.witness => BrassGlyphKind.eye,
        UserRole.cloud => BrassGlyphKind.cloud,
      };

  /// The woodcut-style illustration for each role card, a transparent PNG
  /// (assets/images/role_*.png).
  String get cardArtAsset => switch (this) {
        UserRole.runner => 'assets/images/role_runner.png',
        UserRole.witness => 'assets/images/role_witness.png',
        UserRole.cloud => 'assets/images/role_cloud.png',
      };

  /// Pixel size of [cardArtAsset]'s canvas.
  Size get cardArtSize => const Size(2816, 1536);

  /// Where the opaque artwork sits inside that canvas, in source pixels —
  /// the sheets have large transparent margins, so the card crops to this.
  Rect get cardArtContent => switch (this) {
        UserRole.runner || UserRole.witness => const Rect.fromLTRB(766, 118, 2048, 1426),
        UserRole.cloud => const Rect.fromLTRB(480, 22, 2336, 1522),
      };
}

/// `profiles.role` only ever stores 'runner'/'witness' in the live database
/// — Cloud access is a separate grant (`cloud_admin_church_id`), not a role
/// value (see supabase/migrations/002_grants_and_cloud_access.sql). `cloud`
/// stays a legal enum value here purely so `UserRole.cloud` keeps working as
/// the in-app "which shell am I viewing" marker.
extension UserRoleDb on UserRole {
  String get dbValue => switch (this) {
        UserRole.runner => 'runner',
        UserRole.witness => 'witness',
        UserRole.cloud => 'cloud',
      };
}

UserRole userRoleFromDb(String value) => switch (value) {
      'runner' => UserRole.runner,
      'witness' => UserRole.witness,
      'cloud' => UserRole.cloud,
      _ => throw ArgumentError('Unknown user_role: $value'),
    };
